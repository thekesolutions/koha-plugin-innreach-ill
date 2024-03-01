#!/usr/bin/perl

#
# Copyright 2019 Theke Solutions
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

use Koha::Plugin::Com::Theke::INNReach;

use Koha::Script qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $verbose;
my $local_server;
my $central_server;
my $dry_run = 0;

my $result = GetOptions(
    'v|verbose'        => \$verbose,
    'local_server=s'   => \$local_server,
    'central_server=s' => \$central_server,
    'dry_run'          => \$dry_run
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --local_server      Only sync specified local_server
    --central_server    Only sync the specified central server agencies
    --dry_run           Don't make any changes
    -v | --verbose      Verbose output

_USAGE_
}

my $response;

my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

my @central_servers = @{ $plugin->central_servers };
@central_servers = grep { $_ eq $central_server } @central_servers
    if $central_server;

unless ( scalar @central_servers > 0 ) {
    print_usage();
    print STDERR "No central servers to sync.\n";
}

print STDOUT "Central servers:\n"
    if $verbose and scalar @central_servers > 0;

foreach my $central_server (@central_servers) {
    $response = $plugin->contribution($central_server)->get_agencies_list( { centralServer => $central_server } );

    print STDOUT "$central_server\n"
        if $verbose;
    print STDOUT "\tLocal servers:\n"
        if $verbose and scalar @{$response} > 0;
    foreach my $server ( @{$response} ) {

        next if $local_server and $server->{localCode} ne $local_server;

        print STDOUT "\t\t* " . $server->{localCode} . "\n"
            if $verbose;

        my $local_server = $server->{localCode};
        my $agency_list  = $server->{agencyList};

        foreach my $agency ( @{$agency_list} ) {

            my $agency_id   = $agency->{agencyCode};
            my $description = $agency->{description};

            print STDOUT "\t\t\t- $description ($agency_id)\n"
                if $verbose;

            my $patron_id = $plugin->get_patron_id_from_agency(
                {
                    central_server => $central_server,
                    agency_id      => $agency_id,
                    plugin         => $plugin
                }
            );

            my $patron;

            unless ($dry_run) {
                if ($patron_id) {

                    # Update description
                    $plugin->update_patron_for_agency(
                        {
                            plugin         => $plugin,
                            agency_id      => $agency_id,
                            description    => $description,
                            local_server   => $local_server,
                            central_server => $central_server
                        }
                    );
                } else {

                    # Create it
                    $plugin->generate_patron_for_agency(
                        {
                            plugin         => $plugin,
                            agency_id      => $agency_id,
                            description    => $description,
                            local_server   => $local_server,
                            central_server => $central_server
                        }
                    );
                }
            }
        }
    }
}

1;
