//
//  BMSocialShare.m
//  BMSocialShare
//
//  Created by Vinzenz-Emanuel Weber on 04.11.11.
//  Copyright (c) 2011 Blockhaus Medienagentur. All rights reserved.
//  www.blockhaus-media.com
//

#import "BMSocialShare.h"
#import "CallToPlatform.h"



@interface BMSocialShare()



typedef enum apiCall {
    kAPILogout,
    kAPIGraphUserPermissionsDelete,
    kDialogPermissionsExtended,
    kDialogRequestsSendToMany,
    kAPIGetAppUsersFriendsNotUsing,
    kAPIGetAppUsersFriendsUsing,
    kAPIFriendsForDialogRequests,
    kDialogRequestsSendToSelect,
    kAPIFriendsForTargetDialogRequests,
    kDialogRequestsSendToTarget,
    kDialogFeedUser,
    kAPIFriendsForDialogFeed,
    kDialogFeedFriend,
    kAPIGraphUserPermissions,
    kAPIGraphMe,
    kAPIGraphUserFriends,
    kDialogPermissionsCheckin,
    kDialogPermissionsCheckinForRecent,
    kDialogPermissionsCheckinForPlaces,
    kAPIGraphSearchPlace,
    kAPIGraphUserCheckins,
    kAPIGraphUserPhotosPost,
    kAPIGraphUserVideosPost,
} apiCall;


- (void)facebookPermissions:(NSArray *)permissions;


@end




@implementation BMSocialShare


@synthesize facebook = _facebook;
@synthesize delegate = _delegate;



+ (BMSocialShare *)sharedInstance
{
    static BMSocialShare *gInstance = NULL;
    
    @synchronized(self)
    {
        if (gInstance == NULL)
            gInstance = [[self alloc] init];
    }
    return(gInstance);
}


- (id)init
{
    self = [super init];
    if (self) {
        
        // detect Facebook APP ID from bundle plist
        _appId = nil;
        NSArray *bundleURLTypesArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        if (bundleURLTypesArray) {
            for (int bundleURLTypesArrayItem = 0; bundleURLTypesArrayItem < bundleURLTypesArray.count && _appId == nil; bundleURLTypesArrayItem++) {
                NSDictionary *bundleURLTypesDictionary = [bundleURLTypesArray objectAtIndex:bundleURLTypesArrayItem];
                NSArray *bundleURLSchemesArray = [bundleURLTypesDictionary objectForKey:@"CFBundleURLSchemes"];
                if (bundleURLSchemesArray) {
                    for (int bundleURLSchemesArrayItem = 0; bundleURLSchemesArrayItem < bundleURLTypesArray.count && _appId == nil; bundleURLSchemesArrayItem++) {

                        NSString *appIdCandidate = [bundleURLSchemesArray objectAtIndex:bundleURLSchemesArrayItem];
                        
                        // is this a proper facebook url scheme ?
                        NSRange range = [appIdCandidate rangeOfString:@"fb"];
                        if(range.length == 2 && range.location == 0) {
                            
                            // do we have a suffix ?
                            NSRange fbIdRange = [appIdCandidate rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
                            if (appIdCandidate.length > fbIdRange.location+1) {
                                NSRange suffixRange = NSMakeRange(fbIdRange.location+1, appIdCandidate.length-fbIdRange.location-1);
                                _urlSchemeSuffix = [appIdCandidate substringWithRange:suffixRange];
                            }

                            _appId = [appIdCandidate substringWithRange:NSMakeRange(2, fbIdRange.location-1)];
                            
                            break;
                        }
                    }
                }
            }
        }
        
        
        // Check App ID:
        // This is really a warning for the developer, this should not
        // happen in a completed app
        if (!_appId) {
            
            UIAlertView *alertView = [[UIAlertView alloc]
                                      initWithTitle:@"Setup Error"
                                      message:@"Missing app ID. You cannot run the app until you provide this in the code."
                                      delegate:self
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil,
                                      nil];
            [alertView show];
            [alertView release];
            
            
        } else {
            
            
            // Check if the authorization callback will work
            NSString *url;
            if (_urlSchemeSuffix) {
                url = [NSString stringWithFormat:@"fb%@%@://authorize", _appId, _urlSchemeSuffix];
            } else {
                url = [NSString stringWithFormat:@"fb%@://authorize", _appId];
            }
                        
            
            // Check if the authorization callback will work
            BOOL bCanOpenUrl = [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:url]];
            if (!bCanOpenUrl) {
                
                UIAlertView *alertView = [[UIAlertView alloc]
                                          initWithTitle:@"Setup Error"
                                          message:@"Invalid or missing URL scheme. You cannot run the app until you set up a valid URL scheme in your .plist."
                                          delegate:self
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil,
                                          nil];
                [alertView show];
                [alertView release];
                
            } else {

                // initialize facebook with default permissions
                if (_urlSchemeSuffix) {
                    NSLog(@"BMSocialShare: Using Facebook APP ID: %@ and URL scheme suffix: %@", _appId, _urlSchemeSuffix);
                } else {
                    NSLog(@"BMSocialShare: Using Facebook APP ID: %@", _appId);
                }

                [self facebookPermissions:[NSArray arrayWithObjects: @"publish_stream", nil]];

            }
            
        }

        
    }
    return self;
}




#pragma mark - Private



-(void)_showAlertWithTitle:(NSString *)title andMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
													message:message
												   delegate:nil 
										  cancelButtonTitle:@"Ok" 
										  otherButtonTitles:nil];
	[alert show];
	[alert release];
}



/**
 * In case there is a post in the queue waiting to be sent.
 */
- (void)_dequeueUnbublishedPost {
    BMFacebookPost *post = [BMFacebookPost postFromUserDefaults];
    if (post) {
        [self facebookPublish:post];
    }
}




#pragma mark - Facebook



/**
 * Check if the facebook app is installed on the device.
 */
- (BOOL)isFacebookAppInstalled {
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"fb://"]];
}



/**
 * There is no need to call login if you only want to share stuff.
 * It is enough to make a call to facebookPublish: !
 * Login is only provided if you want to provide a button to the user to login or logout actively.
 */
- (void)facebookLogin {
    
    if (!_facebook.isSessionValid) {
        [_facebook authorize:_permissions];
        return;
    }
    
    // let the delegate know we are logged in
    if ([_delegate respondsToSelector:@selector(facebookDidLogin)]) {
        [_delegate facebookDidLogin];
    }
    
    //save user Data
    [self facebookRequestUser];

}

/**
 * Logut from facebook.
 * You don't actually need to call logout if you don't REALLY want to!
 */
- (void)facebookLogout {
    [BMFacebookPost deleteLastPostFromUserDefaults];
    [_facebook logout];
}


/**
 * For Facebook Single Sign On (SSO) to work, this method needs to be called
 * from within your AppDelegate:
 *
 * - (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
 *     return [[BMSocialShare sharedInstance] facebookHandleOpenURL: url];
 * }
 * 
 */
- (BOOL)facebookHandleOpenURL:(NSURL *)url {
    if (_facebook != nil) {
        return [_facebook handleOpenURL:url];
    }
    return FALSE;
}



/**
 * Call from within applicationDidBecomeActive to renew our access token
 *
 * - (void)applicationDidBecomeActive:(UIApplication *)application {
 *   [[BMSocialShare sharedInstance] facebookExendAccessToken];
 * }
 *
 */
- (void)facebookExtendAccessToken {
    [_facebook extendAccessTokenIfNeeded];
    [self _dequeueUnbublishedPost];
}


/**
 * Enable Facebook sharing with custom permissions.
 *
 */
- (void)facebookPermissions:(NSArray *)permissions {
    
    if (_facebook == nil && _appId != nil) {
        
        
        if (_urlSchemeSuffix) {
            _facebook = [[[Facebook alloc] initWithAppId:_appId urlSchemeSuffix:_urlSchemeSuffix andDelegate:self] retain];
        } else {
            _facebook = [[[Facebook alloc] initWithAppId:_appId andDelegate:self] retain];
        }
        
        
        
        // try to load previous sessions
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:@"FBAccessTokenKey"] 
            && [defaults objectForKey:@"FBExpirationDateKey"]) {
            _facebook.accessToken = [defaults objectForKey:@"FBAccessTokenKey"];
            _facebook.expirationDate = [defaults objectForKey:@"FBExpirationDateKey"];
        }
        
    }
    
    _permissions = [permissions retain];
    
}



/**
 * Open an inline dialog that allows the logged in user to publish a story to his or
 * her wall.
 */
- (void)facebookPublish:(BMFacebookPost *)post {
    
    // login to Facebook in case we have no session yet
    if (!_facebook.isSessionValid) {
        
        // store the last facebook post parameters before we switch to the facebook app or safari
        [post storeToUserDefaults];
        
        [self facebookLogin];
        
        return;
    }
    
         
    switch (post.type) {
            
        case kPostImageNoDialog:
        {
            [_facebook requestWithGraphPath:@"me/photos"
                                  andParams:post.params
                              andHttpMethod:@"POST"
                                andDelegate:self];
        }
            break;
        case kPostImage:
        {
            BMDialog *dialog = [[BMDialog alloc] initWithFacebook:_facebook post:post delegate:self];
            [dialog show];
            [dialog release];
        }
            break;
            
        default:
        case kPostText:
            [_facebook dialog:@"stream.publish"
                    andParams:post.params
                  andDelegate:self];        
            break;
            
    }

}

- (void)facebookRequestUser {
    [_facebook requestWithGraphPath:@"me" andDelegate:self];
}



#pragma mark - FBRequestDelegate


/**
 * Called when a request returns and its response has been parsed into
 * an object. The resulting object may be a dictionary, an array, a string,
 * or a number, depending on the format of the API response. If you need access
 * to the raw response, use:
 *
 * (void)request:(FBRequest *)request
 * didReceiveResponse:(NSURLResponse *)response
 */
- (void)request:(FBRequest *)request didLoad:(id)result {
    if ([result isKindOfClass:[NSArray class]]) {
        result = [result objectAtIndex:0];
    }
    
    //NSLog(@"RESULT:%@ %@",[request url], result);
    /*
    NSString *photoId = [result objectForKey:@"id"];
    if (photoId) {
        NSLog(@"Uploaded Photo with ID: %@", photoId);        
        //[_facebook requestWithGraphPath:photoId andDelegate:self];
    }
    */
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];
    
    if (! jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        
        const char *url = [[request url] UTF8String];
        const char *text = [jsonString UTF8String];
        
        cocos2d::CallToPlatform::sharedCall()->didRecieveGraphResult(url, text);
    }
    
    
    
/*
    if ([result objectForKey:@"id"]) {
        [self.label setText:@"Photo upload Success"];
    } else {
        [self.label setText:[result objectForKey:@"name"]];
    }
*/
};

/**
 * Called when an error prevents the Facebook API request from completing
 * successfully.
 */
- (void)request:(FBRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"ERROR: %@", [error localizedDescription]);
};





#pragma mark - FBDialogDelegate


/**
 * Called when a UIServer Dialog successfully return.
 */
- (void)dialogDidComplete:(FBDialog *)dialog {
    NSLog(@"dialogDidComplete");
    [BMFacebookPost deleteLastPostFromUserDefaults];
}


/**
 * Called when the dialog is cancelled and is about to be dismissed.
 */
- (void)dialogDidNotComplete:(FBDialog *)dialog {
    NSLog(@"dialogDidNotComplete");
    [BMFacebookPost deleteLastPostFromUserDefaults];
}



#pragma mark - FBSessionDelegate



/**
 * Called when the user successfully logged in.
 */
- (void)fbDidLogin {
    NSLog(@"fbDidLogin");
    
    // store this session for later use
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[_facebook accessToken] forKey:@"FBAccessTokenKey"];
    [defaults setObject:[_facebook expirationDate] forKey:@"FBExpirationDateKey"];
    [defaults synchronize];
    
    
    [self _dequeueUnbublishedPost];
    
    // let the delegate know we are logged in
    if ([_delegate respondsToSelector:@selector(facebookDidLogin)]) {
        [_delegate facebookDidLogin];
    }
    
    // save user data
    
    [self facebookRequestUser];

}

/**
 * Called when the user dismissed the dialog without logging in.
 */
- (void)fbDidNotLogin:(BOOL)cancelled {
    NSLog(@"fbDidNotLogin");
    [BMFacebookPost deleteLastPostFromUserDefaults];
}

/**
 * Called when the user logged out.
 */
- (void)fbDidLogout {
    NSLog(@"fbDidLogout");
    [BMFacebookPost deleteLastPostFromUserDefaults];
}

/**
 * Called when the current session has expired. This might happen when:
 *  - the access token expired
 *  - the app has been disabled
 *  - the user revoked the app's permissions
 *  - the user changed his or her password
 */
- (void)fbSessionInvalidated {
    NSLog(@"fbSessionInvalidated");
    // TODO need to do some more research what needs to happen on this event
    [BMFacebookPost deleteLastPostFromUserDefaults];
}

/**
 * Instead of using the "offline_access" permission it is now 
 */
-(void)fbDidExtendToken:(NSString *)accessToken expiresAt:(NSDate *)expiresAt {
    NSLog(@"token extended");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:accessToken forKey:@"FBAccessTokenKey"];
    [defaults setObject:expiresAt forKey:@"FBExpirationDateKey"];
    [defaults synchronize];
}


#pragma mark -  Twitter

-(BOOL) isTwitterInstalled {
    

    Class tweetComposer = NSClassFromString(@"TWTweetComposeViewController");
    
    if( tweetComposer != nil ) {
        
        if([TWTweetComposeViewController canSendTweet] ) {
            return true;
        } else {
            // The user has no account setup
            return false;
        }
    }
    else {
        // no Twitter integration
        return false;
    }
}

/**
 * Send a tweet. Add an image and/or URL, otherwise set them nil.
 *
 */
-(void)twitterPublishText:(NSString *)text 
                withImage:(UIImage *)image 
                   andURL:(NSURL *)url 
   inParentViewController:(UIViewController *)parentViewController {

    // check if we can tweet using iOS5 built-in Twitter account
    BOOL cansend = FALSE;
	Class tweetComposeViewControllerClass = (NSClassFromString(@"TWTweetComposeViewController"));
	if (tweetComposeViewControllerClass != nil) { 			
		if ([tweetComposeViewControllerClass canSendTweet]) {
			cansend = TRUE;
		}
	}

    
	if (cansend) {
        
        // Set up the built-in twitter composition view controller.
        TWTweetComposeViewController *tweetViewController = [[TWTweetComposeViewController alloc] init];
        
        if (text) {
            [tweetViewController setInitialText:text];
        }
        
        if (image) {
            [tweetViewController addImage:image];
        }
        
        if (url) {
            [tweetViewController addURL:url];
        }
                
                
        [tweetViewController setCompletionHandler:^(TWTweetComposeViewControllerResult result) {
            
            
            
/*
            NSString *output;
            
            switch (result) {
                case TWTweetComposeViewControllerResultCancelled:
                    // The cancel button was tapped.
                    output = @"Tweet cancelled.";
                    break;
                case TWTweetComposeViewControllerResultDone:
                    output = @"Tweet done.";
                    break;
                default:
                    break;
            }
            
            [self performSelectorOnMainThread:@selector(displayText:) withObject:output waitUntilDone:NO];
*/
            // Dismiss the tweet composition view controller.
            [parentViewController dismissModalViewControllerAnimated:YES];
            
            [self performSelector:@selector(didSendPerTwitter) withObject:nil afterDelay:0.5];
        }];
        
        // Present the tweet composition view controller modally.
        [parentViewController presentModalViewController:tweetViewController animated:YES];
        
        
    } else {
        [self _showAlertWithTitle:@"Error" andMessage:@"Twitter is not supported on this device!"];
    }
}

-(void)didSendPerTwitter {
    cocos2d::CallToPlatform::sharedCall()->didSendPerTwitter(true);
}





#pragma mark - Email

-(BOOL)isEmailInstalled {
    if ([MFMailComposeViewController canSendMail]) {
        return true;
    } else {
        return false;
    }
}
-(void)emailPublishText:(NSString *)text
                 isHTML:(BOOL)isHTML
            withSubject:(NSString *)subject
              withImage:(NSString *)imagePath
 inParentViewController:(UIViewController *)parentViewController {
    [self emailPublishText:text isHTML:isHTML withSubject:subject withImage:imagePath recipients:nil inParentViewController:parentViewController];
}


-(void)emailPublishText:(NSString *)text
                 isHTML:(BOOL)isHTML
            withSubject:(NSString *)subject
              withImage:(NSString *)imagePath
             recipients:(NSArray *)recipients
 inParentViewController:(UIViewController *)parentViewController {
    
    
    // check how we can send emails
    BOOL cansend = FALSE;
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
	if (mailClass != nil) { 			
		if ([mailClass canSendMail]) {
			cansend = TRUE;
		}
	}
    
    
    if (parentViewController == nil) {
        return;
    }
    
    _emailParentViewController = parentViewController;
    
    
    if (cansend) {
        
        MFMailComposeViewController *picker = [[MFMailComposeViewController alloc] init];
        picker.mailComposeDelegate = self;
        
        if (subject) {
            [picker setSubject:subject];
        }

        if (text) {
            [picker setMessageBody:text isHTML:isHTML];
        }
        
        if (imagePath) {
            
            NSString *filename = [imagePath lastPathComponent];
            NSString *fileExtension = [filename pathExtension];
            NSString *mimeType = [NSString stringWithFormat:@"image/%@", fileExtension];
            
            NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
            [picker addAttachmentData:imageData mimeType:mimeType fileName:filename];
            
        }

        if (recipients) {

            [picker setToRecipients:recipients];
            
            /*
             // Set up recipients
             NSArray *toRecipients = [NSArray arrayWithObject:@"first@example.com"];
             NSArray *ccRecipients = [NSArray arrayWithObjects:@"second@example.com", @"third@example.com", nil];
             NSArray *bccRecipients = [NSArray arrayWithObject:@"fourth@example.com"];
             
             [picker setToRecipients:toRecipients];
             [picker setCcRecipients:ccRecipients];
             [picker setBccRecipients:bccRecipients];
             */
    
        }

        [parentViewController presentModalViewController:picker animated:YES];
        [picker release];
        
        
    } else {

/*
 NSString *recipients = @"mailto:first@example.com?cc=second@example.com,third@example.com&subject=Hello from California!";
*/
        
        NSMutableString *msg = [NSMutableString stringWithString:@"mailto:"];

        if (recipients) {
            NSString *recipientsString = [recipients componentsJoinedByString:@","];
            if (recipientsString) {
                [msg appendFormat:@"%@&", recipientsString];
            }
        }
        
        if (subject) {
            [msg appendFormat:@"subject=%@", subject];            
        }
        
        if (text) {
            [msg appendFormat:@"&body=%@", text];            
        }

        NSString *email = [msg stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:email]];

    }
    
}



// Dismisses the email composition interface when users tap Cancel or Send. Proceeds to update the message field with the result of the operation.
- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error 
{
	[_emailParentViewController dismissModalViewControllerAnimated:YES];
    [self performSelector:@selector(didSendPerEmail) withObject:nil afterDelay:0.5];
    
}

-(void)didSendPerEmail {
    cocos2d::CallToPlatform::sharedCall()->didSendPerEmail(true);
}




#pragma mark - Memory Management


- (void)dealloc {
    [_facebook release];
    [super dealloc];
}





@end
