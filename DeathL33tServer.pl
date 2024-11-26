#!/usr/bin/perl

################################################################################
# $Id: DeathL33tServer.pl 207 2013-01-07 13:27:03Z n620911 $
################################################################################


use warnings;
use strict;
use POE;
use POE::Component::Server::TCP;
use Data::Dumper;
use Switch;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

################################################################################
# Global variables.  
################################################################################
my %users;			        # The users list
my %weapons;			    # The weapon each user has
my %scores;			        # The score for each user
my %kills;			        # The kills for each user
my %startclock;             # To keep a running total
my $NOWEAPON = "-None-";	# No weapon
my $NONAME   = "Anonymous";	# No name given
my $logger = get_logger();	# The Log4perl logger.
our $VERSION = "0.5b";

# Create the server on port 32080, and start it running.

$logger->info("DeathL33t running on port 32080");
POE::Component::Server::TCP->new
  ( Alias => "chat_server",
    Port               => 32080,
    InlineStates       => { send => \&handle_send },
    ClientConnected    => \&client_connected,
    ClientError        => \&client_error,
    ClientDisconnected => \&client_disconnected,
    ClientInput        => \&client_input,
  );

$logger->info("Calling Run()");
$poe_kernel->run();
exit 0;

# This is used to broadcast messages to the room that are not '$sender'
# To send to EVERYONE just set $sender to 0.

sub broadcast {
    my ( $sender, $message ) = @_;
    my $sendername = $users{$sender};
    # $logger->error(Dumper \%users);
    # $logger->error(Dumper \%weapons);
    foreach my $user ( keys %users ) {
        if ( $user != $sender ) {
            # $poe_kernel->post( $user => send => "$sendername ($user) $message" );
            if ($sender != 0) {
                $poe_kernel->post( $user => send => qq{"$sendername" $message} );
            } else {
                $poe_kernel->post( $user => send => "$message" );
            }
        }
    }
	return;
}

# Handle an outgoing message by sending it to the client.

sub handle_send {
    my ( $heap, $message ) = @_[ HEAP, ARG0 ];
    $heap->{client}->put($message);
    return;
}

# Handle a connection.  Register the new user, and broadcast a message
# to whoever is already connected.

sub client_connected {
    my $session_id           = $_[SESSION]->ID;
    $users{$session_id}      = qq/Anonymous/;
    $scores{$session_id}     = 0;
    $kills{$session_id}      = 0;
    $startclock{$session_id} = 0;
    $weapons{$session_id}    = $NOWEAPON;
    $logger->info("New user $session_id joined.");
    welcome( $session_id );
    return;
}

# The client disconnected.  Remove them from the chat room and
# broadcast a message to whoever is left.

sub client_disconnected {
    my $session_id = $_[SESSION]->ID;
    delete $weapons{$session_id};
    $logger->info("User $session_id has disconnected.");
    broadcast( $session_id, "has left the field of battle." );
    delete $users{$session_id};
    return;
}

# The client socket has had an error.  Remove them from the chat room
# and broadcast a message to whoever is left.

sub client_error {
    my $session_id = $_[SESSION]->ID;
    broadcast( $session_id, "disconnected." );
    delete $users{$session_id};
    $_[KERNEL]->yield("shutdown");
    return;
}

# Broadcast client input to everyone in the chat room.

sub client_input {
    my ( $kernel, $session, $input ) = @_[ KERNEL, SESSION, ARG0 ];
    my $session_id = $session->ID;
    # Switch statement needed for commands.
    switch($input) {
	case /^name/i { name_change($session_id, $input); }
	case /^weapon/i { weapon_change($session_id, $input); }
	case /^look/i { look_around($session_id, $input); }
	case /^scan/i { look_around($session_id, $input); }
	case /^kill/i { kill_player($session_id, $input); }
	case /^help/i { game_help($session_id, $input); }
	case /^score/i { show_scores($session_id, $input); }
	case /^quit/i { $_[KERNEL]->yield("shutdown"); }
	else { $logger->error("$session_id typed in some junk:$input" ); }
    } # end switch for the commands.
    return;
}

# Client has issued the 'name' command.
sub name_change {
    my ( $session_id, $input) = @_;
    my $proposed_name = q{};
    if ($input =~ m/^name *([^ ]*).*/i) { 
            $proposed_name = $1;
            if((length($proposed_name) > 12) || (length($proposed_name) < 3)) {
                broadcast ( $session_id, "is being a spaz with the name.");
                $poe_kernel->post( $session_id => send => "You try to name yourself $proposed_name." );
                $poe_kernel->post( $session_id => send => "You give up with that and decide to call yourself killme." );
                $proposed_name = "killme";
            }
            my ($existing_name) = grep { $users{$_} eq $proposed_name } keys %users;
            if ($existing_name) {
                # I think this is a name collision.
                $logger->error("Name collision Detected : [$existing_name] and [$proposed_name]"); 
                $poe_kernel->post( $session_id => send => "That name is already taken.  Try another." );
                return;
                
            }
            
            
            $users{$session_id} = $proposed_name;
            $poe_kernel->post( $session_id => send => "You are now known as $proposed_name." );
            if ($weapons{$session_id} ne $NOWEAPON) {
                broadcast ( $session_id, "has entered the fray.");
             }
    } # no name given.
    return;
}

# Client has issued the 'weapon' command.
sub weapon_change {
    my ( $session_id, $input) = @_;
    my $prev_weapon = $weapons{$session_id};
    if ($input =~ m/^weapon *([^ ].*)/i) { 
	my $proposed_name = $1;
	# Let's spank them for being fruity with the weapon names.
        if((length($proposed_name) > 30) || (length($proposed_name) < 3)) {
                broadcast ( $session_id, "is being a spaz with the weapon name.");
                $poe_kernel->post( $session_id => send => "You try to yield $proposed_name." );
                $poe_kernel->post( $session_id => send => "You give up with that and try a crowbar instead." );
                $proposed_name = "a limp crowbar";
		}
	# I didn't get an article with the weapon, so I'll just slap a 'the' in front.
	if ($proposed_name !~ m/(a|an|the) /i) {
		$proposed_name = "the ".$proposed_name;
	}
        $weapons{$session_id} = $proposed_name;
        $poe_kernel->post( $session_id => send => "You yield $proposed_name." );
    if (($users{$session_id} ne "Anonymous") && ($prev_weapon eq $NOWEAPON )) {
    	broadcast ( $session_id, "has entered the fray.");
        $poe_kernel->post( $session_id => send => "You jump into the fray." );
	} else {
    	broadcast ( $session_id, "has picked a new weapon.");
        }
    }
    return;
}

# Client has issued the 'kill' command.
sub kill_player {
    my ( $session_id, $input) = @_;
    my $pscore = 0;
    # If they can't be targetted because they have no name or weapon, then they can't scan.
    if ($users{$session_id} eq "Anonymous") {
    	$poe_kernel->post( $session_id => send => "You cannot kill until you have a name." );
	return;
	}
    if ($weapons{$session_id} eq $NOWEAPON) {
    	$poe_kernel->post( $session_id => send => "You cannot kill until you are armed and dangerous." );
	return;
	}
    $poe_kernel->post( $session_id => send => "Ok, you attempt to kill!" );
    if ($input =~ m/^kill *(.*)/i) { 
	my $victim_name = $1;
        if(killable_by_name($victim_name)) { 
		my $victim_session = session_id_by_name($victim_name);
        # If the victim and the killer are the same . . .
        if ($victim_session == $session_id) {
		    $poe_kernel->post( $session_id => send => "You attempt to kill yourself, but miss." );
		    broadcast ( $session_id, "sits down drooling.");
            return;
        }
		my  $weapon = $weapons{$session_id};
		my  $killer = $users{$session_id};
		$poe_kernel->post( $session_id => send => "You slay $victim_name with $weapon!" );
		$poe_kernel->post( $victim_session => send => "$killer slays you with $weapon!" );
        # Get current score of victim.  Keep it to send to them and zero it out.
        $pscore = $scores{$victim_session};
        $scores{$victim_session} = 0;
		$poe_kernel->post( $victim_session => send => "Your score [$pscore] -> [0]!" );

        # Increment the kill count for the killer.
        if ($kills{$session_id} == 0) {
          $scores{$session_id}  += ($pscore + 1);
        } else {
           $scores{$session_id} += $kills{$session_id} * ($pscore + 1) + (time() - $startclock{$session_id});
        }
        $startclock{$session_id} =  time();
        $kills{$session_id} = $kills{$session_id} + 1;
        my $killerscore = $scores{$session_id};
        

        # Zero out kill count on victim and disarm them.
        $kills{$victim_session}      = 0;
		$weapons{$victim_session}    = $NOWEAPON;
        $startclock{$victim_session} = 0;
		broadcast ( $session_id, "kills $victim_name with $weapon!");
        broadcast ( 0 , "$victim_name had a score of [$pscore]");
        broadcast ( $session_id , "now  has a score of [$killerscore]");
        } # if killable 
	else {
    		broadcast ( $session_id, "has attemted  to kill someone, but failed.!");
		$poe_kernel->post( $session_id => send => "You fail!  Are you sure $victim_name is here?  And are they armed?" );
	}
    } # If we get to here it's because they didn't supply a name.
    return;
}

# Client has issued the 'look' command.
sub look_around {
    my ( $session_id, $input) = @_;
    my $weapon;
    my $username;

    # If they can't be targetted because they have no name or weapon, then they can't scan.
    if ($users{$session_id} eq "Anonymous") {
    	$poe_kernel->post( $session_id => send => "You cannot scan until you have a name." );
	return;
	}
    if ($weapons{$session_id} eq $NOWEAPON) {
    	$poe_kernel->post( $session_id => send => "You cannot scan until you are armed and dangerous." );
	return;
	}
	
    $poe_kernel->post( $session_id => send => "You scan for a victim:" );
    foreach my $user ( keys %users ) { 
        $logger->error("Scanning user $user");
        $weapon = $weapons{$user};
	$username = $users{$user};
        if ( $user == $session_id ) {
            $poe_kernel->post( $session_id => send => "You are armed with $weapon." );
        }
        else {
		# Ignore Anonymous or users without weapons.  They aren't targets yet.
		if (($username ne "Anonymous") &&  ($weapon ne $NOWEAPON)) {
            $poe_kernel->post( $session_id => send => "$username ($user) stands ready to kill with $weapon." );
		}
        } # end else others in the room.
    } # end foreach

    broadcast ( $session_id, "is scanning for a victim.");
    return;
}

# Client has issued the 'look' command.
sub show_scores {
    my ( $session_id, $input) = @_;
    my $userscore = 0;
    my $username  = q{};
    my $prettyscore = q{};
    my $ranking = 0;

    $poe_kernel->post($session_id => send => "####### The SCORES ###################################################");
    my @keys = sort { $scores{$b} <=> $scores{$a} } keys(%scores); # b then a to reverse the sort order. Large to small
    foreach my $user ( @keys ) { 
        $ranking++;
        $logger->error("Scoring user $user");
        $userscore = $scores{$user};
	    $username = $users{$user};
        $prettyscore = sprintf("# %3d : %20.20s -> [%9d]",$ranking,$username,$userscore);
        # $poe_kernel->post($session_id => send => "$username [$userscore]");
        $poe_kernel->post($session_id => send => $prettyscore);
    } # end foreach
    $poe_kernel->post($session_id => send => "######################################################################");
    $poe_kernel->post($session_id => send => "");
    return;
}

# Client has issued the 'help' command.
sub game_help {
    my ( $session_id, $input) = @_;
    broadcast ( $session_id, "is looking for help.");
    $poe_kernel->post( $session_id => send => "Game Help \n".
	"* - These commands require that the user have a handle (aka name) in the game before they work.\n".
	"Command\tParam\tDescription\n".
	"name\thandle\tChanges your name to the specified handle.\n".
	"weapon\twep\tChanges your weapon to the specified wep.\n".
	"look\t[none]\t*This is what you use too look around.\n".
	"scan\t[none]\t*This is what you use too look around.\n".
	"score\t[none]\tShow all the current user scores.\n".
	"kill\tvictim\t*attempts to kill the victim using your weapon.\n".
	"help\t[none]\tThis help screen.\n".
	"\n\nVersion: $VERSION"
	);
    return;
}

# Return the session_id given a name.
# Returns a 0 if no user was found by that name.
sub session_id_by_name {
	my ($username) = @_;
	foreach my $user ( keys %users ) {
		if ( $username eq $users{$user} ) {
			return $user;
		}
	} # end foreach
	return 0;
}

# Print a welcome message
# http://www.network-science.de/ascii/ to create the banner.  Then added the extra \\ s
# Font: epic   Reflection: no   Adjustment: left   Stretch: no      Width: 80    Text: DeathL33t
sub welcome {
    my ( $session_id, $input) = @_;
    $poe_kernel->post( $session_id => send => 
    "Welcome to DeathL33T!  Where Zork meets Call Of Duty.\n\n\n\n".
	" ______   _______  _______ _________          _       ______   ______ _________\n".
	"(  __  \\ (  ____ \\(  ___  )\\__   __/|\\     /|( \\     / ___  \\ / ___  \\\\__   __/\n".
	"| (  \\  )| (    \\/| (   ) |   ) (   | )   ( || (     \\/   \\  \\\\/   \\  \\  ) (   \n".
	"| |   ) || (__    | (___) |   | |   | (___) || |        ___) /   ___) /  | |   \n".
	"| |   | ||  __)   |  ___  |   | |   |  ___  || |       (___ (   (___ (   | |   \n".
	"| |   ) || (      | (   ) |   | |   | (   ) || |           ) \\      ) \\  | |   \n".
	"| (__/  )| (____/\\| )   ( |   | |   | )   ( || (____/Y\\___/  //\\___/  /  | |   \n".
	"(______/ (_______/|/     \\|   )_(   |/     \\|(_______|______/ \\______/   )_(   \n".
    "##################################################################################\n".
    "Game Help \n".
	"* - These commands require that the user have a handle (aka name) in the game before they work.\n".
	"Command\tParam\tDescription\n".
	"name\thandle\tChanges your name to the specified handle.\n".
	"weapon\twep\tChanges your weapon to the specified wep.\n".
	"look\t[none]\t*This is what you use too look around.\n".
	"scan\t[none]\t*This is what you use too look around.\n".
	"score\t[none]\tShow all the current user scores.\n".
	"kill\tvictim\t*attempts to kill the victim using your weapon.\n".
	"help\t[none]\tThis help screen.\n".
	"\n\nVersion: $VERSION \n".
    "######################################################################\n".
    "At any time, you can type 'help' to get the help menu again.\n"
	);
}

# killable name?
sub killable_by_name {
	my ($victim_name) = @_;
	my $victim_session = session_id_by_name($victim_name);
	if ($victim_session < 2) { return 0; }
	if ($users{$victim_session} eq "Anonymous") { return 0; }
	if ($weapons{$victim_session} eq $NOWEAPON) { return 0; }
	return 1;
}
