#/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Getopt::Long;
use List::MoreUtils qw(none);
use Try::Tiny       qw( catch try );

use Koha::Plugin::Com::Theke::INNReach;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $borrowing;
my $command;
my $help;
my $list_commands;
my $owning;
my $request_id;
my $skip_api_req;

my $result = GetOptions(
    'borrowing'     => \$borrowing,
    'command=s'     => \$command,
    'help'          => \$help,
    'list_commands' => \$list_commands,
    'owning'        => \$owning,
    'request_id=s'  => \$request_id,
    'skip_api_req'  => \$skip_api_req,
);

unless ($result) {
    print_usage();
    say "Not sure what wen't wrong";
    exit 1;
}

if ($help) {
    print_usage();
    exit 0;
}

unless ( $request_id || $list_commands ) {
    print_usage();
    say "--request_id or --list_commands is mandatory";
    exit 1;
}

unless ( $command || $list_commands ) {
    print_usage();
    say "--command or --list_commands is mandatory";
    exit 1;
}

if ( $owning && $borrowing ) {
    print_usage();
    say "--owning and --borrowing are mutually exclusive";
    exit 1;
} elsif ( !( $owning || $borrowing ) ) {
    print_usage();
    say "--owning or --borrowing need to be specified";
    exit 1;
}

my @valid_owning    = qw(cancel_request final_checkin item_shipped);
my @valid_borrowing = qw(item_received item_in_transit receive_unshipped);

if ($list_commands) {
    if ($owning) {
        print_usage();
        say "Valid owning site options are: " . join( ', ', @valid_owning );
        exit 1;
    } else {
        print_usage();
        say "Valid borrowing site options are: " . join( ', ', @valid_borrowing );
        exit 1;
    }
}

if ($owning) {
    if ( none { $_ eq $command } @valid_owning ) {
        print_usage();
        say "'$command' is and invalid command. Valid options are: " . join( ', ', @valid_owning );
        exit 1;
    }
} else {
    if ( none { $_ eq $command } @valid_borrowing ) {
        print_usage();
        say "'$command' is and invalid command. Valid options are: " . join( ', ', @valid_borrowing );
        exit 1;
    }
}

my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

sub print_usage {
    print <<_USAGE_;

This script takes care of triggering an INNReach command.

Options:

    --request_id <id>      An ILL request ID

    --owning               An owning site command will be executed
    --borrowing            A borrowning site command will be executed

    --command <command>    The command to be run

    --skip_api_req         Skip actual API interaction (useful for cleanup) [optional]

    --help                 This help

_USAGE_
}

my $c =
    ($owning)
    ? INNReach::Commands::OwningSite->new( { plugin => $plugin } )
    : INNReach::Commands::Borrowing->new( { plugin => $plugin } );

my $req = $plugin->get_ill_rs()->find($request_id);

try {
    $c->$command($req, { skip_api_req => $skip_api_req });
} catch {
    if ( ref($_) eq 'INNReach::Ill::RequestFailed' ) {
        warn sprintf(
            "[innreach] [ill_req=%s]\t%s request error: %s (X-IR-Allowed-Circulation: %s)",
            $req->id,
            $_->method,
            $_->response->decoded_content // '',
            $_->response->headers->header('X-IR-Allowed-Circulation') // '<empty>'
        );
    } else {
        warn sprintf(
            "[innreach] [ill_req=%s]\tunhandled error: %s",
            $req->id,
            $_
        );
    }

    exit 1;
};

1;

