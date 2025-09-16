package t::lib::Mocks::INNReach;

# Copyright 2025 Theke Solutions
#
# This file is part of The INNReach plugin.
#
# The INNReach plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use YAML::XS;
use C4::Context;
use Koha::Plugin::Com::Theke::INNReach;

=head1 NAME

t::lib::Mocks::INNReach - Mock INNReach plugin for testing

=head1 SYNOPSIS

    use t::lib::Mocks::INNReach;
    
    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype
    });
    
    # With custom configuration
    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            'd2ir' => {
                contribution => {
                    enabled => 0,
                    included_items => { ccode => ['x', 'y'] }
                }
            }
        }
    });

=head1 DESCRIPTION

Provides a standardized way to create INNReach plugin instances with
test configuration and essential system setup, following Koha's t::lib::Mocks pattern.
Includes bootstrap functionality to ensure tests can run independently.

=head1 METHODS

=head2 new

    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,   # Koha::Library object
        category => $category,  # Koha::Patron::Category object  
        itemtype => $itemtype,  # Koha::ItemType object
        config   => $hashref    # Optional: override configuration
    });

Creates a new INNReach plugin instance with test configuration and performs
essential system setup for test independence.

=cut

sub new {
    my ( $class, $params ) = @_;

    my $library  = $params->{library}  || die "library parameter required";
    my $category = $params->{category} || die "category parameter required";
    my $itemtype = $params->{itemtype} || die "itemtype parameter required";
    my $config   = $params->{config};

    # Perform essential system setup (from bootstrap.pl)
    $class->_setup_system_preferences();
    $class->_setup_plugin_state();

    # Default configuration structure
    my $default_config = {
        'd2ir' => {
            api_base_url => 'https://test-api.example.com',
            api_token_base_url => 'https://test-api.example.com',
            client_id => 'test_client',
            client_secret => 'test_secret',
            localServerCode => 'test1',
            mainAgency => 'test2',
            require_patron_auth => 1,
            partners_library_id => $library->branchcode,
            partners_category => $category->categorycode,
            library_to_location => {
                $library->branchcode => {
                    location => 'test1',
                    description => 'Test Library'
                }
            },
            local_to_central_itype => {
                $itemtype->itemtype => 200
            },
            local_to_central_patron_type => {
                $category->categorycode => 200
            },
            central_to_local_itype => {
                200 => 'TEST_BK'
            },
            contribution => {
                enabled => 1,
                included_items => { ccode => [ 'a', 'b', 'c' ] },
                excluded_items => { ccode => [ 'c', 'd', 'e' ] }
            },
            default_item_type => $itemtype->itemtype,
            dev_mode => 1
        }
    };

    my $final_config;
    if ($config) {
        # Merge custom config with defaults
        $final_config = { %$default_config };
        foreach my $server (keys %$config) {
            if (exists $final_config->{$server}) {
                # Deep merge for existing servers
                foreach my $key (keys %{$config->{$server}}) {
                    if (ref $config->{$server}->{$key} eq 'HASH' && 
                        ref $final_config->{$server}->{$key} eq 'HASH') {
                        # Merge hash values
                        $final_config->{$server}->{$key} = {
                            %{$final_config->{$server}->{$key}},
                            %{$config->{$server}->{$key}}
                        };
                        # Remove keys that are explicitly set to undef
                        foreach my $subkey (keys %{$config->{$server}->{$key}}) {
                            if (!defined $config->{$server}->{$key}->{$subkey}) {
                                delete $final_config->{$server}->{$key}->{$subkey};
                            }
                        }
                    } else {
                        # Replace scalar values, or delete if undef
                        if (defined $config->{$server}->{$key}) {
                            $final_config->{$server}->{$key} = $config->{$server}->{$key};
                        } else {
                            delete $final_config->{$server}->{$key};
                        }
                    }
                }
            } else {
                # Add new server
                $final_config->{$server} = $config->{$server};
            }
        }
    } else {
        $final_config = $default_config;
    }

    # Convert to YAML
    my $config_yaml = YAML::XS::Dump($final_config);

    # Create plugin and store configuration
    my $plugin = Koha::Plugin::Com::Theke::INNReach->new();
    $plugin->store_data( { configuration => $config_yaml } );

    return $plugin;
}

=head2 _setup_system_preferences

Sets up essential system preferences for INNReach testing.

=cut

sub _setup_system_preferences {
    my ($class) = @_;

    # Set required system preferences
    C4::Context->set_preference( 'ILLModule', 1 );
    C4::Context->set_preference( 'RESTBasicAuth', 1 );
}

=head2 _setup_plugin_state

Ensures INNReach plugin is enabled and other plugins are disabled.

=cut

sub _setup_plugin_state {
    my ($class) = @_;

    my $dbh = C4::Context->dbh;

    # Enable INNReach plugin
    $dbh->do(q{
        UPDATE plugin_data SET plugin_value=1
        WHERE plugin_key='__ENABLED__'
          AND plugin_class='Koha::Plugin::Com::Theke::INNReach'
    });

    # Disable other plugins to avoid conflicts
    $dbh->do(q{
        UPDATE plugin_data SET plugin_value=0
        WHERE plugin_key='__ENABLED__'
          AND plugin_class<>'Koha::Plugin::Com::Theke::INNReach'
    });
}

1;
