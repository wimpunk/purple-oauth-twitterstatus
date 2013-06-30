use Purple;
use XML::XPath;
use XML::XPath::XMLParser;
# moved to twitter::lite as the normal twitter crashes
use Net::Twitter::Lite::WithAPIv1_1;
use POSIX;
use Data::Dumper;

use strict;
use warnings;

# trying to add version to the version number
my ($VERSION) = q$Revision: 31 $ =~ /(\d+)/;

our %PLUGIN_INFO = (
    perl_api_version => 2,
    name => 'Twitter Oauth Status',
    version => '0.4.2-r'.$VERSION,
    summary => 'Use a Twitter feed as your status message.',
    description => 'Use a Twitter feed as your status message.  '
		. 'Based on the twitter status update from '
		. 'http://code.google.com/p/pidgin-twitterstatus/',
    author => 'wimpunk <wimpunk\@gmail.com>',
    url => 'http://www.tisnix.be/twitter-oauth-status/',
    load => 'plugin_load',
    unload => 'plugin_unload',
    prefs_info => 'prefs_info_cb'
);

#Begin Global Variables
my $pref_root = '/plugins/core/gtk-wimpunk-twitterstatus';
my $log_category = 'twitterstatus';
my $user_agent = "pidgin-twitterstatus/$PLUGIN_INFO{version}";
my $source_agent = 'pidgintwitterstatus';

my $plugin_instance;
my $active_update_timer;
my $client = Net::Twitter::Lite::WithAPIv1_1->new(
		#traits         => ['API::REST','OAuth'],
		consumer_key    => "IkU8CVvABj0ZeOQrAQDrvg",
		consumer_secret => "kDB5lMR0VoQEbLIrbuvLD72j7XrozVgEyHP0q4csc",
		);
#End Global Variables

sub find_latest_tweet
{
	my ($twitter_statuses) = @_;
	my $out_status;

	my $pref_ignore_replies = Purple::Prefs::get_bool("$pref_root/ignore_replies");
	my $pref_filter_regex = Purple::Prefs::get_string("$pref_root/filter_regex");

	Purple::Debug::info($log_category, "Preferences: "
			    ."ignore_replies = $pref_ignore_replies, "
			    ."filter_regex = '$pref_filter_regex'\n");

	my $last_seen_id = Purple::Prefs::get_int("$pref_root/state/last_seen_id");
	my $last_seen_id_dirty;
	
	foreach my $this_status (@$twitter_statuses) {

		# my $this_status_id = $this_status->find('id')->string_value;
		my $this_status_id = $this_status->{'id'};
		if ($this_status_id > $last_seen_id) {
			$last_seen_id = $this_status_id;
			$last_seen_id_dirty = 1;
		}
		# my $this_status_message = $this_status->('text')->string_value;
		my $this_status_message = $this_status->{'text'};
		Purple::Debug::info($log_category, "Found twitter status $this_status_id: '$this_status_message'\n");

		my $emsg = do {
			if ($this_status_id <= 0) { 'invalid status ID' }
			elsif (length($this_status_message) <= 1) { 'too short' }
			elsif ($pref_ignore_replies &&
			       ($this_status->{'in_reply_to_user_id'} ||
				$this_status->{'in_reply_to_status_id'} ||
				$this_status->{'in_reply_to_screen_name'} )) { 'was a reply to someone' }
			elsif ($pref_filter_regex && $this_status_message =~ m/$pref_filter_regex/) { 'matched the discard filter' }
		};
		if ($emsg) {
			Purple::Debug::info($log_category, "Skipping status message: $emsg\n");
		} else {
			$out_status = $this_status;
			last;
		}
	}
	Purple::Prefs::set_int("$pref_root/state/last_seen_id", $last_seen_id) if $last_seen_id_dirty;
	return $out_status;
}

sub update_active_tweet
{
	my $tweet = shift;
	return unless $tweet;

	#my $tweet_id = $tweet->find('id')->string_value;
	my $tweet_id = $tweet->{'id'};
	return if $tweet_id <= Purple::Prefs::get_int("$pref_root/state/last_updated_id");

	my $tweet_message = $tweet->{'text'};
	Purple::Prefs::set_int("$pref_root/state/last_updated_id", $tweet_id);
	Purple::Prefs::set_string("$pref_root/state/last_updated_text", $tweet_message);

	return $tweet_id;
}

sub get_savedstatuses_to_update {
	return map { (Purple::SavedStatus::find($_) ||
		      Purple::SavedStatus::new($_, 2)) }
	  (split /\s*,\s*/, Purple::Prefs::get_string("$pref_root/savedstatuses_to_update"));
}

sub refresh_purple_status
{
	my $twitter_status = Purple::Prefs::get_string("$pref_root/state/last_updated_text");
	my $status_message = Purple::Prefs::get_string("$pref_root/status_template");
	$status_message =~ s/\%\%/\%/g;
	$status_message =~ s/\%s/$twitter_status/g;

    	my $now_string = localtime;
    	$status_message =~ s/\%t/$now_string/g;

	Purple::Debug::info($log_category, "Refreshing purple status to: $status_message\n");

	my @update_list = get_savedstatuses_to_update();
	my @dirty_list = (grep { $_->get_message() ne $status_message } @update_list);
	$_->set_message($status_message) foreach @dirty_list;

	my $cur_status = Purple::SavedStatus::get_default();
	my $cur_status_title = $cur_status->get_title();
	return unless $cur_status_title;
	$_->activate foreach (grep { $_->get_title() eq $cur_status_title } @dirty_list);
}

sub merge_twitter_response
{
	my ($twitter_response, $status_list_xpath) = @_;
	return unless $twitter_response;

	my $tweet_id = update_active_tweet (find_latest_tweet($twitter_response));
	refresh_purple_status();
	return $tweet_id;
}

sub fetch_url_cb
{
	my $twitter_response = shift;
	merge_twitter_response $twitter_response, '/statuses/status';
}

sub update_status
{
	if ($client->authorized) {
		Purple::Debug::info($log_category, "Update status since we are authorized\n");
		my $timeout = shift;
		my $max = Purple::Prefs::get_int("$pref_root/max_statuses_to_fetch");
		my $last = Purple::Prefs::get_int("$pref_root/state/last_seen_id");
# TODO: for some reason it doesn't work if we use since_id = 0
		my $statusses;
		eval {
			if ($last > 0 ) {
				Purple::Debug::info($log_category, "Getting statusses: started\n");
				$statusses =  $client->user_timeline({since_id => $last, count => $max});
				Purple::Debug::info($log_category, "Getting statusses: finished\n");
			} else {
				$statusses =  $client->user_timeline({count => $max});
			}
			merge_twitter_response  $statusses, '/statuses/status';
		};
		if ( my $err = $@ ) {
# die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
			# http://search.cpan.org/~mmims/Net-Twitter-3.10000/lib/Net/Twitter.pod
			if ($err->isa('Net::Twitter::Error')) {

				Purple::Debug::info($log_category, "HTTP Response Code: ". $err->code. "\n");
				Purple::Debug::info($log_category, "HTTP Message......: ". $err->message. "\n");
				Purple::Debug::info($log_category, "Twitter error.....: ". $err->error. "\n");
			}
			# TODO else we should just disconnect
			Purple::Debug::info($log_category, "Error getting status\n");
		}
	}	
}


sub schedule_status_update
{
	my $delay = ((shift) || Purple::Prefs::get_int("$pref_root/poll_interval"));

	# If there's a timer already ticking, remove that first
	if ($active_update_timer) {
		Purple::Debug::info($log_category, "Cancelling current scheduled status update\n");
		Purple::timeout_remove($active_update_timer);
		undef $active_update_timer;
	}

	$active_update_timer = Purple::timeout_add($plugin_instance, $delay, \&timeout_cb);
	Purple::Debug::info($log_category, "Scheduling next status update in $delay seconds\n");
}

sub timeout_cb
{
	undef $active_update_timer;
	Purple::Debug::info($log_category, "Starting the sequence.  Pidgin's timer expired.\n");
	my $poll_interval = Purple::Prefs::get_int("$pref_root/poll_interval");

	my $access_token = Purple::Prefs::get_string("$pref_root/access_token");
	Purple::Debug::info($log_category, "time_out: access_token: $access_token\n");
	my $access_secret = Purple::Prefs::get_string("$pref_root/access_secret");
	Purple::Debug::info($log_category, "time_out: access_secret: $access_secret\n");

	if (not ( $client->authorized )) {
		Purple::Debug::info($log_category, "time_out: not authorized\n");
		$poll_interval = 30;
# not authorized, try the pin
		my $pin = Purple::Prefs::get_string("$pref_root/access_pin");	
		Purple::Debug::info($log_category, "time_out: try pin $pin\n");
		if ($pin) {
			Purple::Debug::info($log_category, "time_out: pin $pin was set\n");
			my ($access_token, $access_secret) =
				$client->request_access_token(verifier => $pin);
			Purple::Prefs::set_string("$pref_root/access_pin","");
			Purple::Prefs::set_string("$pref_root/access_token",$access_token);
			Purple::Prefs::set_string("$pref_root/access_secret",$access_secret);
		}
	} 
	if ($access_token && $access_secret) {
		$client->access_token($access_token);
		$client->access_token_secret($access_secret);
	}

	update_status $poll_interval;
	schedule_status_update $poll_interval;
}

sub send_tweet
{
	my $status = shift;
	return unless $status;
	return unless Purple::Prefs::get_bool("$pref_root/sendstatus");

	Purple::Debug::info($log_category, "Tweeting back: $status\n");
	$status = Purple::Util::url_encode($status);

	my $pref_username = Purple::Prefs::get_string("$pref_root/twitterusername");
	my $pref_password = Purple::Prefs::get_string("$pref_root/twitterpassword");
	my $api_root = Purple::Prefs::get_string("$pref_root/api_root");

	my $pid = open (KID_TO_READ, '-|');
	unless ($pid) { # child
		exec ('curl', '--user', "$pref_username:$pref_password",
		      '--data', "status=$status", '--data', "source=$source_agent",
		      "$api_root/statuses/update.xml") || die "Unable to exec for tweet update: $!";
		# Not reached here
	}
	my $twitter_response;
	{
		local $/ = undef;
		$twitter_response = <KID_TO_READ>;
		close KID_TO_READ;
	}
	return $twitter_response;
}

# saved status change callback
#  Tries to modifies the status message
#  TODO: it would be nice if we could use something like "twitter: %s" as status message
sub saved_status_changed_cb
{
	my ($new_status, $old_status) = @_;

	# For some reason, calling methods on arguments passed don't work, so fetch afresh
	$new_status = Purple::SavedStatus::get_default();
	if (! $new_status->is_transient()) {
		Purple::Debug::info($log_category, "Changed to a Saved Status, ignoring\n");
		return;
	}
	my $status_message_escaped = $new_status->get_message();
	$status_message_escaped = '' unless defined $status_message_escaped; 
	# There should be a better way to unescape the XML encoded string
	# TODO: remove the XML stuff so it can be removed completely
	# See bugreport: this one is uninitialized on startup
	my $status_xml = XML::XPath->new(xml=>"<status>$status_message_escaped</status>");
	my @status_nodes = $status_xml->find('/status')->get_nodelist();
	my $new_status_message = ($status_nodes[0])->string_value;

	my $twitter_response = send_tweet($new_status_message);

	if (merge_twitter_response $twitter_response, '/status') {
		# We successfully updated status, let's reset timeout
		schedule_status_update;
		my $switch_to = Purple::Prefs::get_string("$pref_root/savedstatus_to_switch_after_tweetback");
		if ($switch_to) {
			my $saved_status = Purple::SavedStatus::find($switch_to);
			# This would make a recursive call, but we only activate a saved status
			$saved_status->activate() if ($saved_status && ! $saved_status->is_transient());
		}
	}
}

sub plugin_init
{
    return %PLUGIN_INFO;
}

sub ok_cb_test{
    # The $fields is passed to the callback function when the button is clicked.
    # To access a specific field, it must be extracted from $fields by name.
    my $fields = shift;
    my $account = Purple::Request::Fields::get_account($fields, "acct_test");
    my $int = Purple::Request::Fields::get_integer($fields, "int_test");
    my $choice = Purple::Request::Fields::get_choice($fields, "ch_test");
}
sub cancel_cb_test{
    # Cancel does nothing but is equivalent to the ok_cb_test
}


sub plugin_load
{
    $plugin_instance = shift;
    Purple::Debug::info($log_category, "plugin_load() - Twitter Status Feed.\n");

    # Here we are adding a set of preferences
    #  The second argument is the default value for the preference.
    Purple::Prefs::add_none("$pref_root");
    Purple::Prefs::add_string("$pref_root/twitterusername", '');
    Purple::Prefs::add_string("$pref_root/twitterpassword", '');
	# twitter api key should be getted by a buttom

	# authentication url
    Purple::Prefs::add_string("$pref_root/access_url", '');
	# pin for previous authenticatien url
    Purple::Prefs::add_string("$pref_root/access_pin", '');
	# return oauth token after validation url
    Purple::Prefs::add_string("$pref_root/access_token", '');
	# return oauth secret after validation url
	Purple::Prefs::add_string("$pref_root/access_secret", '');

    Purple::Prefs::add_string("$pref_root/filter_regex", '');
    Purple::Prefs::add_bool("$pref_root/sendstatus", '');
    Purple::Prefs::add_int("$pref_root/poll_interval", 120);
    Purple::Prefs::add_bool("$pref_root/ignore_replies", 1);
    Purple::Prefs::add_int("$pref_root/max_statuses_to_fetch", 0);
    Purple::Prefs::add_string("$pref_root/api_root", 'http://twitter.com');
    Purple::Prefs::add_string("$pref_root/status_template", '%s');
    Purple::Prefs::add_string("$pref_root/savedstatuses_to_update", 'Twitter');
    Purple::Prefs::add_string("$pref_root/savedstatus_to_switch_after_tweetback", '');

    Purple::Prefs::add_none("$pref_root/state");
    Purple::Prefs::add_int("$pref_root/state/last_seen_id", 0);
    Purple::Prefs::add_int("$pref_root/state/last_updated_id", 0);
    Purple::Prefs::add_string("$pref_root/state/last_updated_text", '');

	# Adding the callback
	# (where do we find documetation about this?)
    Purple::Signal::connect(Purple::SavedStatuses::get_handle(), 'savedstatus-changed', $plugin_instance, \&saved_status_changed_cb, '');

    # Discard last seen ID optimizations for the first run, in case plugin logic has changed
    Purple::Prefs::set_int("$pref_root/state/last_seen_id", 0);
	# Oauth settings 
	# This is done pretty basic
	Purple::Prefs::set_string("$pref_root/access_pin","");
	Purple::Prefs::set_string("$pref_root/access_url","");

    schedule_status_update 10;

}

sub plugin_unload
{
	undef $_ foreach ($active_update_timer, $plugin_instance);
	Purple::Debug::info($log_category, "plugin_unload() - Twitter Status Feed.\n");
}

sub prefs_info_cb
{
    my ($frame, $ppref);
	
	# TODO: this is not really a good place but just a quick fix
	my $access_token = Purple::Prefs::get_string("$pref_root/access_token");
	my $access_secret = Purple::Prefs::get_string("$pref_root/access_secret");

	if ($access_token && $access_secret) {
		$client->access_token($access_token);
		$client->access_token_secret($access_secret);
	}

    # The first step is to initialize the Purple::Pref::Frame that will be returned
    $frame = Purple::PluginPref::Frame->new();

    $frame->add(Purple::PluginPref->new_with_label('Twitter Account Information'));

	if (not ( $client->authorized )) {
		# The client is not yet authorized: Do it now

		# TODO I tried a few different ways to get a clickable link in the preferences window
		# the current version gives the user a link which has to be pasted to the favorit browser

		# update the authorisation url
		Purple::Debug::info($log_category, "not authorized, try ". $client->get_authorization_url."\n");
		Purple::Prefs::set_string("$pref_root/access_url",,$client->get_authorization_url);
		$frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/access_url", 'Goto next Twitter Url'));
		$frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/access_pin", 'and enter Twitter Pin'));
	} else {
		Purple::Debug::info($log_category, "authorized\n");
		$frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/access_token", 'Twitter Access Token'));
		$frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/access_secret", 'Twitter Access Token Secret'));
	}

    $frame->add(Purple::PluginPref->new_with_label('Options'));
    $ppref = Purple::PluginPref->new_with_name_and_label("$pref_root/poll_interval", 'Poll Interval (in seconds)');
    $ppref->set_bounds(40, 900); # Twitter has 100 per hour IP limit, which means 36 seconds between polls
    $frame->add($ppref);
    $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/ignore_replies", 'Ignore reply tweets'));
    $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/status_template", 'Status message template'));
	# list of the status messages which will get updated
    $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/savedstatuses_to_update", 'Saved statuses to update (comma separated)'));

    # $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/sendstatus", 'Tweet my status message when I change it in Pidgin'));
    # $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/savedstatus_to_switch_after_tweetback", 'Switch to this saved status after tweeting back'));

    $frame->add(Purple::PluginPref->new_with_label('Advanced Options'));
    $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/filter_regex", 'Ignore regexp for tweets'));
    $frame->add(Purple::PluginPref->new_with_name_and_label("$pref_root/api_root", 'API Root URL'));
    $ppref = Purple::PluginPref->new_with_name_and_label("$pref_root/max_statuses_to_fetch", 'Maximum statuses to request');
    $ppref->set_bounds(1, 100); # Twitter anyway doesn't return more than 20
    $frame->add($ppref);

    return $frame;
}

######################################################################
# vim: ai ts=4 sw=4 tw=78 :

__END__
