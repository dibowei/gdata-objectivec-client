/* Copyright (c) 2010 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "OAuthSampleAppController.h"

@interface OAuthSampleAppController ()
- (void)signInToGoogle;
- (void)signInToTwitter;

- (void)signOut;
- (BOOL)isSignedIn;

- (void)doAnAuthenticatedAPIFetch;

- (void)updateUI;

- (void)displayErrorThatTheCodeNeedsATwitterConsumerKeyAndSecret;

- (void)setAuthentication:(GDataOAuthAuthentication *)auth;
@end


@implementation OAuthSampleAppController

static NSString *const kAppServiceName = @"OAuth Sample: Google Contacts";

- (void)awakeFromNib {
  // get the saved authentication, if any, from the keychain
  GDataOAuthAuthentication *auth;
  auth = [GDataOAuthWindowController authForInstalledAppFromKeychainForApplicationServiceName:kAppServiceName];
  [self setAuthentication:auth];

  // this is optional:
  //
  // we'll watch for the "hidden" fetches that occur to obtain tokens
  // during authentication, and start and stop our indeterminate progress
  // indicator during the fetches
  //
  // usually, these fetches are very brief
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(signInFetchStateChanged:)
             name:kGDataOAuthFetchStarted
           object:nil];
  [nc addObserver:self
         selector:@selector(signInFetchStateChanged:)
             name:kGDataOAuthFetchStopped
           object:nil];

  [self updateUI];
}

- (void)dealloc {
  [mAuth release];
  [super dealloc];
}

- (BOOL)isGoogleButtonSelected {
  int tag = [[mRadioButtons selectedCell] tag];
  return (tag == 0);
}

#pragma mark -

- (BOOL)isSignedIn {
  BOOL isSignedIn = [mAuth canAuthorize];
  return isSignedIn;
}

- (IBAction)signInOutClicked:(id)sender {
  if (![self isSignedIn]) {
    // sign in
    if ([self isGoogleButtonSelected]) {
      [self signInToGoogle];
    } else {
      [self signInToTwitter];
    }
  } else {
    // sign out
    [self signOut];
  }
  [self updateUI];
}

- (void)signOut {
  // remove the stored authentication from the keychain
  [GDataOAuthWindowController removeParamsFromKeychainForApplicationServiceName:kAppServiceName];

  [GDataOAuthWindowController revokeTokenForGoogleAuthentication:mAuth];

  // discard our retains authentication object
  [self setAuthentication:nil];

  [self updateUI];
}

- (void)signInToGoogle {
  [self signOut];

  // For GData applications, the scope is available as
  //   NSString *scope = [[service class] authorizationScope]
  NSString *scope = @"http://www.google.com/m8/feeds/";

  // display the autentication sheet
  GDataOAuthWindowController *windowController;
  windowController = [[[GDataOAuthWindowController alloc] initWithScope:scope
                                                               language:nil
                                                         appServiceName:@"OAuth Sample: Google Contacts"
                                                         resourceBundle:nil] autorelease];
  [windowController signInSheetModalForWindow:mMainWindow
                                     delegate:self
                             finishedSelector:@selector(windowController:finishedWithAuth:error:)];
  }

- (void)signInToTwitter {
  // Note: to use this sample, you need to fill in a valid consumer key and
  // consumer secret provided by Twitter for their API
  //
  // http://twitter.com/apps/
  NSString *myConsumerKey = @"";
  NSString *myConsumerSecret = @"";

  if ([myConsumerKey length] == 0 || [myConsumerSecret length] == 0) {
    [self displayErrorThatTheCodeNeedsATwitterConsumerKeyAndSecret];
    return;
  }

  [self signOut];
  NSURL *requestURL = [NSURL URLWithString:@"http://twitter.com/oauth/request_token"];
  NSURL *authorizeURL = [NSURL URLWithString:@"http://twitter.com/oauth/authorize"];
  NSURL *accessURL = [NSURL URLWithString:@"http://twitter.com/oauth/access_token"];
  NSString *scope = @"http://api.twitter.com/";

  GDataOAuthAuthentication *auth;
  auth = [[[GDataOAuthAuthentication alloc] initWithSignatureMethod:kGDataOAuthSignatureMethodHMAC_SHA1
                                                        consumerKey:myConsumerKey
                                                         privateKey:myConsumerSecret] autorelease];
  [auth setCallback:@"http://www.google.com/OAuthCallback"];

  GDataOAuthWindowController *windowController;
  windowController = [[[GDataOAuthWindowController alloc] initWithScope:scope
                                                               language:nil
                                                        requestTokenURL:requestURL
                                                      authorizeTokenURL:authorizeURL
                                                         accessTokenURL:accessURL
                                                         authentication:auth
                                                         appServiceName:@"OAuth Sample: Twitter"
                                                         resourceBundle:nil] autorelease];
  [windowController signInSheetModalForWindow:mMainWindow
                                     delegate:self
                             finishedSelector:@selector(windowController:finishedWithAuth:error:)];
}

- (void)windowController:(GDataOAuthWindowController *)windowController
        finishedWithAuth:(GDataOAuthAuthentication *)auth
                   error:(NSError *)error {
  if (error != nil) {
    // Authentication failed (perhaps the user denied access, or closed the
    // window before granting access)
    NSLog(@"Authentication error: %@", error);
    NSData *responseData = [[error userInfo] objectForKey:@"data"]; // kGDataHTTPFetcherStatusDataKey
    if ([responseData length] > 0) {
      // show the body of the server's authentication failure response
      NSString *str = [[[NSString alloc] initWithData:responseData
                                             encoding:NSUTF8StringEncoding] autorelease];
      NSLog(@"%@", str);
    }

    [self setAuthentication:nil];
  } else {
    // Authentication succeeded
    //
    // At this point, we either use the authentication object to explicitly
    // authorize requests, like
    //
    //   [auth authorizeRequest:myNSURLMutableRequest]
    //
    // or store the authentication object into a GData service object like
    //
    //   [[self contactService] setAuthorizer:auth];

    // save the authentication object
    [self setAuthentication:auth];

    // Just to prove we're signed in, we'll attempt an authenticated fetch for the
    // signed-in user
    [self doAnAuthenticatedAPIFetch];
  }

  [self updateUI];
}

#pragma mark -

- (void)doAnAuthenticatedAPIFetch {
  NSString *urlStr;
  if ([self isGoogleButtonSelected]) {
    // Google Contacts feed
    urlStr = @"http://www.google.com/m8/feeds/contacts/default/thin";
  } else {
    // Twitter status feed
    urlStr = @"http://api.twitter.com/1/statuses/home_timeline.json";
  }

  NSURL *url = [NSURL URLWithString:urlStr];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [mAuth authorizeRequest:request];

  // Synchronous fetches like this are a really bad idea in Cocoa applications
  //
  // For a very easy async alternative, we could use GDataHTTPFetcher
  NSError *error = nil;
  NSURLResponse *response = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest:request
                                       returningResponse:&response
                                                   error:&error];

  if (data) {
    // API fetch succeeded
    NSString *str = [[[NSString alloc] initWithData:data
                                           encoding:NSUTF8StringEncoding] autorelease];
    NSLog(@"API response: %@", str);
  } else {
    // fetch failed
    NSLog(@"API fetch error: %@", error);
  }
}

#pragma mark -

- (void)displayErrorThatTheCodeNeedsATwitterConsumerKeyAndSecret {
  NSBeginAlertSheet(@"Error", nil, nil, nil, mMainWindow,
                    self, NULL, NULL, NULL,
                    @"The sample code requires a valid Twitter consumer key"
                    " and consumer secret to sign in to Twitter");
}

- (void)signInFetchStateChanged:(NSNotification *)note {
  // this just lets the user know something is happening during the
  // sign-in sequence's "invisible" fetches to obtain tokens
  //
  // the type of token obtained is available as
  //   [[note userInfo] objectForKey:kGDataOAuthFetchTypeKey]
  //
  if ([[note name] isEqual:kGDataOAuthFetchStarted]) {
    [mSpinner startAnimation:self];
  } else {
    [mSpinner stopAnimation:self];
  }
}

- (void)updateUI {
  // update the text showing the signed-in state and the button title
  if ([self isSignedIn]) {
    // signed in
    [mTokenField setStringValue:[mAuth token]];
    [mSignInOutButton setTitle:@"Sign Out"];
  } else {
    // signed out
    [mTokenField setStringValue:@"Not signed in"];
    [mSignInOutButton setTitle:@"Sign In..."];
  }
}

- (void)setAuthentication:(GDataOAuthAuthentication *)auth {
  [mAuth autorelease];
  mAuth = [auth retain];
}

@end
