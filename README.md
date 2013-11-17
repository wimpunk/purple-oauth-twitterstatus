# purple-oauth-twitterstatus

Use a Twitter feed as your purple/pidgin status message.

# Introduction

Use your Twitter account as your Pidgin status message.  This plugin is based on [pidgin-twitterstatus](http://code.google.com/p/pidgin-twitterstatus) but uses oauth authentication which should be more save since it doesn't need a password.

I decided to work on that version because the pidgin-twitterstatus
plugin needed a public profile.  Using oauth prevents the need of a public profile or the need to provide your password in every application. Currently you even have to use oauth. The old one isn't supported anymore.

# Download
The latest version can be downloaded by pressing the zip-button or you can try [this link](../../archive/master.zip)
The lastest version uses `Net::Twitter::Lite`.
An old version can be found on [launchpad](http://launchpad.net/purple-oauth-twitterstatus)

# Installation
You need the latest Net::Twitter module to get it working.
It depends on the oauth module included in Net::Twitter since 3.00. It's been tested against libnet-twitter-perl included in debian-testing.
If your linux doesn't support the correct version of Net::Twitter you can install it running

    sudo perl -MCPAN -e 'install Net::Twitter'

If you are running windows you can try the instruction found on  
[this issue](http://code.google.com/p/pidgin-status-to-twitter/issues/detail?id=2)
After installing the correct library, you just have to copy the plugin to your plugins direcory. On linux you can use the `~/.purple/plugins` directory. On windows, you can use the %APPDATA%\.purple\plugins directory. If you installed it correctly, you can enable it after restarting pidgin.

# Configuration

When you go to the preferences windows, you will see an url and
pin to configure the oauth. Open the url in your favorite browser and authenticate the application. After pidgin gets authenticated correctly, you will see a token and a secret when looking at the preferences.

# Questions and more
<!-- 
If you have any questions, you can ask them on [launchpad](https://answers.launchpad.net/purple-oauth-twitterstatus)
-->
If you have any questions, you can ask them at [the issue section](../../issues/new)

# oauthtest.pl

What? it does some test. It connects to twitter and gets your latest tweets.

You should copy the access_token and access_token_secret to a file named token.
On the next check the testprogram will use those tokens to connect to twitter.

# todo
<!-- changed to issue syntax back to normal because it only works
     on issues and stuff. -->
* verify the use of the plugin name
* redirect all launchpad stuff to this new location
* make an easier the authentication easier.
* better authentication system.
