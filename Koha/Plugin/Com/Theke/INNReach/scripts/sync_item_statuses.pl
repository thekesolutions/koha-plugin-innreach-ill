#/usr/bin/perl

# Copyright 2021 Theke Solutions
#
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

use DDP;

use Getopt::Long;
use List::MoreUtils qw(any);
use Try::Tiny       qw(catch try);

use Koha::Plugin::Com::Theke::INNReach;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $central_server;
my $where;
my $help;

my $result = GetOptions(
    'central_server=s' => \$central_server,
    'where=s'          => \$where,
    'help'             => \$help,
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

unless ($central_server) {
    print_usage();
    say "--central_server is missing (mandatory)";
    exit 1;
}

sub print_usage {
    print <<_USAGE_;

Options:

    --central_server       Contribute to the specified central server (mandatory)
    --where                SQL WHERE conditions on items [NOT IMPLEMENTED]

_USAGE_
}

my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

unless ( any { $_ eq $central_server } $plugin->central_servers ) {    # valid?
    print_usage();
    say "$central_server is not a valid configured central server!";
    exit 1;
}

my $contribution = $plugin->contribution($central_server);

my $dbh = C4::Context->dbh;

my $contributed_items_table = $plugin->get_qualified_table_name('contributed_items');

my @item_ids = map { $_->[0] } $dbh->selectall_array(
    qq{
    SELECT item_id FROM $contributed_items_table
    WHERE central_server = ?;
}, undef, $central_server
);

if ( scalar @item_ids > 0 ) {
    print STDOUT "# Syncing items:\n";
    foreach my $item_id (@item_ids) {
        try {
            my $result = $contribution->update_item_status(
                {
                    itemId        => $item_id,
                    centralServer => $central_server,
                }
            );
            if ($result) {
                warn p($result);
                print STDOUT "\t$item_id\t => ERROR\n";
            } else {
                print STDOUT "\t$item_id\t => OK\n";
            }
        } catch {
            warn "$_";
        };
    }
} else {
    print STDOUT "No items to sync.\n";
}

1;
