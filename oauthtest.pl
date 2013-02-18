#!/usr/bin/perl
# based on http://log.damog.net/2009/05/twitters-oauth-perl/
# http://stereonaut.net/index.php?s=oauth
# use Net::Twitter::OAuth;
use Net::Twitter;
use Data::Dumper;
use Storable;

sub save_tokens {
	$local_access_token = $_[0];
	$local_access_secret = $_[1];
	print("token:  $local_access_token\n");
	print("secret: $local_access_secret\n");
	my %access =();
	$access{'token'} = $local_access_token; 
	$access{'secret'} = $local_access_secret;

	print ("** saved: \n");
	warn Dumper(\%access);
	store \%access,'token';

}

sub restore_tokens {
	eval {
		my $access = retrieve('token');
		print ("** restored: \n");
		print("restored token:  %access->{'token'}\n");
		print("restored secret: %access->{'secret'}\n");
		print ("** dump retored access: \n");

		warn Dumper(\$access);
	
		return($access->{'token'},$access->{'secret'});
	} or do {
		print("No token to restore\n");
		return ('','');
	}
}
my $client = Net::Twitter->new(
		traits         => ['API::REST','OAuth'],
		consumer_key    => "IkU8CVvABj0ZeOQrAQDrvg",
		consumer_secret => "kDB5lMR0VoQEbLIrbuvLD72j7XrozVgEyHP0q4csc",
		);

# we should not restore if the file isn't there
my ($access_token, $access_token_secret) = restore_tokens();

if ($access_token && $access_token_secret) {
	print("restored\n");
	print("access_token: $access_token\n");
	print("access_token_secret: $access_token_secret\n");
	$client->access_token($access_token);
	$client->access_token_secret($access_token_secret);
}

# reading pin
$data_file="pin";
my $newpin = "";
if (open(DAT, $data_file)){
	@raw_data=<DAT>;
	close(DAT);

	foreach $pin (@raw_data)
	{
		chomp($pin);
		print "pin: $pin\n";
		$newpin = $pin;
		break;
	}

# my $newpin = $pin;
	print "newpin: $newpin\n";
}

if (not ( $client->authorized )) {
# The client is not yet authorized: Do it now
	print "Authorize this app at ", $client->get_authorization_url, " and hit RET\n";

	$newpin = <STDIN>; # wait for input
		chomp($newpin);

	my($access_token, $access_token_secret) = 
		$client->request_access_token(verifier => $newpin);
#save_tokens($access_token, $access_token_secret); # if necessary
	print("access_token: $access_token\n");
	print("access_token_secret: $access_token_secret\n");
}
# my $res = $client->update({ status => 'me ownz oauth!!1' });


eval {
# my $statuses = $client->friends_timeline({ since_id => $high_water, count => 100 });
	my $statuses = $client->user_timeline({ count => 10 });
	for my $status ( @$statuses ) {
		print "$status->{time} <$status->{user}{screen_name}> $status->{text}\n";
	}
};
if ( my $err = $@ ) {
	die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

	warn "HTTP Response Code: ", $err->code, "\n",
		 "HTTP Message......: ", $err->message, "\n",
		 "Twitter error.....: ", $err->error, "\n";
}
# warn Dumper(\$client);
$client->end_session;

warn Dumper(\$client);
