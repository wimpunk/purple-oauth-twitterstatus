# purple-oauth-twitterstatus

Use a Twitter feed as your purple/pidgin status message.

# instructions
As instructed on [the homepage](http://www.tisnix.be/twitter-oauth-status) 
you just have to place this plugin in `$HOME/.purple/plugins` after installing 
the `Net::Twitter::Lite` library in perl.  After restarting pidgin, you will
be able to enable the plugin and configure it as instructed.

# oauthtest.pl
What? it does some test. It connects to twitter and gets your latest tweets.

You should copy the access_token and access_token_secret to a file named token.
On the next check the testprogram will use those tokens to connect to twitter.
