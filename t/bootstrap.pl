#!/usr/bin/perl

# This file is part of the INNReach plugin
#
# The INNReach plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use DDP;
use File::Slurp;
use Try::Tiny qw(catch try);

use C4::Context;
use Koha::Database;

# For generating random data
use t::lib::TestBuilder;

use Koha::Plugin::Com::Theke::INNReach;

my $builder = t::lib::TestBuilder->new;
my $plugin  = Koha::Plugin::Com::Theke::INNReach->new;

C4::Context->set_preference( 'ILLModule', 1 )
    && step("ILLModule set");

my $config_string = read_file('/kohadevbox/plugins/innreach/t/config.yaml');
$plugin->store_data(
    {
        configuration => $config_string,
    }
);
step("Configuration loaded (from t/config.yaml)");

if (
    $builder->build_object(
        {
            class => 'Koha::Libraries',
            value => { branchcode => 'ILL', pickup_location => 1 }
        }
    )
    )
{
    step("Added 'ILL' library");

} else {
    step("Add 'ILL' library [SKIPPED]");
}

sub step {
    my ($message) = @_;

    print STDOUT "* $message\n";
}

1;
