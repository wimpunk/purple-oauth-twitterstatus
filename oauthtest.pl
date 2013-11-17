#!/usr/bin/perl
# based on http://log.damog.net/2009/05/twitters-oauth-perl/
# http://stereonaut.net/index.php?s=oauth
# use Net::Twitter::OAuth;
# switched back to the Net::Twitter
use strict;
use warnings;
use Net::Twitter;
#use Net::Twitter::Lite::WithAPIv1_1;
use Data::Dumper;
use Storable;
use DateTime;
use Date::Parse;


sub save_tokens {

	my %access = @_;
	print("saving token:  $access{'token'}\n");
	print("saving secret: $access{'secret'}\n");

	print ("** saved: \n");
## does not compute
	warn Dumper(\%access);
# warn Dumper(\$access);
	print ("** end dump \n");
	store (\%access,'access');

}

sub restore_tokens {
	eval {
		my %access = %{ retrieve('access') };
		print ("** restored: \n");
		print("restored token:  $access{'token'}\n");
		print("restored secret: $access{'secret'}\n");
		print ("** dump restored access: \n");

	    print ("*** begin dump \n");
		warn Dumper(\%access);
	    print ("*** end dump \n");

		return(\%access);

	} or do {
		print("!!! Could not restore token\n");
		my %hash = ();
		return (\%hash);
	}
}
#my $client = Net::Twitter::Lite::WithAPIv1_1->new(
my $client = Net::Twitter->new(
		traits         => [qw/API::RESTv1_1 InflateObjects/],
		consumer_key    => "IkU8CVvABj0ZeOQrAQDrvg",
		consumer_secret => "kDB5lMR0VoQEbLIrbuvLD72j7XrozVgEyHP0q4csc",
		);

# we should not restore if the file isn't there
my ($access) = restore_tokens();
#my $access = {};

print("--- access ---\n");
warn Dumper($access);
print("----------\n");

if ($access->{'token'}) {
	print("restored\n");
	print("access_token: $access->{'token'}\n");
	print("access_token_secret: $access->{'secret'}");

	$client->access_token($access->{'token'});
	$client->access_token_secret($access->{'secret'});
}


# reading pin
my $data_file="pin";
my $newpin = "";
if (open(DAT, $data_file)){
	my @raw_data=<DAT>;
	close(DAT);

	foreach my $pin (@raw_data)
	{
		chomp($pin);
		print "pin: $pin\n";
		$newpin = $pin;
		last;
	}

# my $newpin = $pin;
	print "newpin: $newpin\n";
}

if (not ( $client->authorized )) {
# The client is not yet authorized: Do it now
	print "Authorize this app at ", $client->get_authorization_url, ", enter the pin and hit RET\n";

	$newpin = <STDIN>; # wait for input
		chomp($newpin);

	my %access;
	($access{'token'}, $access{'secret'}) = 
		$client->request_access_token(verifier => $newpin);
    save_tokens(%access); # if necessary
	print("access_token: $access{'token'}\n");
	print("access_token_secret: $access{'secret'}\n");
}
# my $res = $client->update({ status => 'me ownz oauth!!1' });

eval {
# my $statuses = $client->friends_timeline({ since_id => $high_water, count => 100 });
	my $statuses = $client->user_timeline({ count => 1 });
	my $timeout_time = DateTime::Duration->new( hours => 48);
	for my $status ( @$statuses ) {
		my $age = DateTime->now - $status->created_at;

		if (DateTime::Duration->compare( $timeout_time, $age) == -1) {
					print('msg to old: timeout time');
					}

		print "$status->{created_at} <$status->{user}{screen_name}> $status->{text} $age\n";
	}
};
if ( my $err = $@ ) {
	die $@ unless $err->isa('Net::Twitter::Error');

	warn "HTTP Response Code: ", $err->code, "\n",
		 "HTTP Message......: ", $err->message, "\n",
		 "Twitter error.....: ", $err->error, "\n";
}
# warn Dumper(\$client);
$client->end_session;

warn Dumper(\$client);
