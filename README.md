# koha-plugin-innreach

This project implements a plugin integrating Koha with the INN-Reach ILL service.

## WIP
This project is work-in-progress

## Goal
When finished, this plugin will implement:
* The required endpoints for INN-Reach -> Koha communication
* Implement a [Koha ILL backend](https://wiki.koha-community.org/wiki/ILL_backends) that does the required Koha -> INNReach communication too

## Problems to solve
* We need to hook all biblio and items CRUD operations to report back to the INNReach Central Server (contributing records).
This could be easily done in rebuild_zebra.pl, but we might need a separate server.

# Implemented

## Record/data contribution

The plugin implements methods that cover all data contribution options.

### Implemented required endpoints
```
    POST /api/v1/contrib/innreach/v2/getbibrecord/{bibId}/{centralCode}
```

TODO: They aren't yet packed into a set of maintenance scripts/daemons that keep
things up-to-date. _Koha::Plugin::Com::Theke::INNReach::Contribution_ implements
all documented interactions.

## Owning site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

### Implemented required endpoints

```
    POST /api/v1/contrib/innreach/v2/circ/itemhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemreceived/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/intransit/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelitemhold/{trackingId}/{centralCode}
```

## Borrowing site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

### Implemented required endpoints

```
    POST /api/v1/contrib/innreach/v2/circ/verifypatron
    POST /api/v1/contrib/innreach/v2/circ/patronhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/finalcheckin/{trackingId}/{centralCode}
```

# TODO

The following endpoints (taking out cancelrequest) have no clear fit in the documented
flows and require further conversations to get implemented properly.

```
    PUT  /api/v1/contrib/innreach/v2/circ/ownerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/borrowerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/claimsreturned/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/transferrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/receiveunshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/returnuncirculated/{trackingId}/{centralCode} 
```

## Preparation

### Dependencies

Install the missing deps:
```
  $ sudo apt install \
           libnet-oauth2-authorizationserver-perl \
           libcryptx-perl \
           libdata-printer-perl
```

##  Settings

* Enable _RESTOAuth2ClientCredentials_ syspref
* Create an _ILL_ patron category
* Create a patron for INN-Reach
* Add permissions to the patron
* Create an API client_id/client_secret pair

## ILL
ILL needs to be set in _koha-conf.xml_ (replace _${INSTANCE}_ for your instance name):

```
<interlibrary_loans>
     <!-- Path to where Illbackends are located on the system
          - This setting should normally not be touched -->
     <backend_directory>/var/lib/koha/${INSTANCE}/plugins/Koha/Illbackends</backend_directory>
     <branch>M</branch>
     <!-- How should we treat staff comments?
          - hide: don't show in OPAC
          - show: show in OPAC -->
     <staff_request_comments>hide</staff_request_comments>
     <!-- How should we treat the reply_date field?
          - hide: don't show this field in the UI
          - any other string: show, with this label -->
     <reply_date>hide</reply_date>
     <!-- Where should digital ILLs be sent?
          - borrower: send it straight to the borrower email
          - branch: send the ILL to the branch email -->
     <digital_recipient>branch</digital_recipient>
     <!-- What patron category should we use for p2p ILL requests?
          - By default this is set to 'ILLLIBS' -->
     <partner_code>ILL</partner_code>
 </interlibrary_loans>
 ```

Then __enable__ the _ILLModule_ system preference.

## Install the plugin/ILL backend
Download the latest _.kpz_ file from the [releases](https://github.com/thekesolutions/koha-plugin-innreach/releases) page.
Install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).

## Plugin configuration
The plugin configuration is an HTML text area in which a _YAML_ structure is pasted. The available options
are maintained on this document.

```
    centralServers:
        - d2ir
    api_base_url: https://rssandbox-api.iii.com
    client_id: a_client_id
    client_secret: a_client_secret
    localServerCode: koha1
    mainAgency: code2
    require_patron_auth: true
    local_patron_id: 93
    library_to_location:
        CPL: code1
        MPL: code2
    local_to_central_itype:
        BK: 200
        CF: 201
        CR: 200
        MP: 200
        MU: 201
        MX: 201
        REF: 202
        VM: 201
    local_to_central_patron_type:
        AP: 200
        CH: 200
        DR: 200
        DR2: 200
        ILL: 202
        LIBSTAFF: 201
        NR: 200
        SR: 202
    contribution:
        max_retries: 10
```

### Options

* __centralServers__: This is a list of INN-Reach central servers. A Koha instance can be part of more than one ILL network, so several can be specified. No specific business rules are designed to be set for each of them (yet) but there's room for that. The code is designed to act against a specific central server. i.e. the one that initiates the circulation flow. Records and holdings contribution are designed to be done for all configured central servers with no options to specify what is contributed where.
* __localServerCode__: INN-Reach will assign a code to each server interacting with them. So each Koha instance is assigned a code, and it needs to be specified here.
* __api_base_url__, __client_id__ and __client_secret__: This information needs to be provided by INN-Reach for the kick-off. It's the base URL into which Koha will make the API requests, and the id/secret pair for the _OAuth2 client credentials_ flow.
* __require_patron_auth__: Whether or not we require the patron to input their credentials on the INN-Reach site. The code implement both use cases, but authenticating hasn't been tested on the wild due to the latency to set the environments. If there's a concrete use case we will have the chance to iron it.
* __local_patron_id__: This is the _borrowernumber_ for the Koha user we created for INN-Reach to use (with permissions and API keys). This isn't supposed to be needed, but depending on the Koha version it wasn't possible to get the current patron from the stash. FIXME: This workaround should be removed once we are sure Koha _18.11.x_ is fixed (patched in master by us).
* __library_to_location__: INN-Reach defines unique codes for 'agencies' (branches). _library_to_location_ is a hash for mapping Koha's branchcodes to INN-Reach-defined agency codes. See the [kick-off checklist](#kick-off-checklist).
* __local_to_central_itype__: Hash for mapping Koha's itemtype codes to INN-Reach-defined ones. See the [kick-off checklist](#kick-off-checklist).
* __local_to_central_patron_type__: Hash for mapping Koha's patron categories into INN-Reach-defined ones. See the [kick-off checklist](#kick-off-checklist).
* __contribution__: Data contribution specific settings. _max_retries_ defines how many retries are to be accepted before failing to contribute a record/item.

*Note*: Central patron types and central item types can be fetched using the defined methods
using the Contribution class.

## Kick-off checklist

### Agency codes
INN-Reach assigns unique codes for branches/pickup locations. This needs to be requested to be able to set things.

### Item types
INN-Reach defines unique ids to item types based on the exchange with the different insitutions using the central server. An exchange needs to take place to either adjust the mapping to the existing item types (if the Koha instance is joining a previsouly existing INN-Reach central server) or to suggest a list of itemtypes matching Koha's. The mapping needs to be done anyway, as Koha uses strings, and they use integers.

You can check the defined central server item types by running:

```
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --item_types
```

### Patron types
INN-Reach defines unique ids to patron types based on the exchange with the different insitutions using the central server. An exchange needs to take place to either adjust the mapping to the existing patron types (if the Koha instance is joining a previsouly existing INN-Reach central server) or to suggest a list of patron types matching Koha's. The mapping needs to be done anyway, as Koha uses strings, and they use integers.

You can check the defined central server item types by running:

```
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --patron_types
```

## Setting initial locations
The use case covered by this implementation is that locations are Koha's branches (i.e. they are really pickup locations).
One of the first configuration steps is to populate INN-Reach with our current locations. Use the _contribute_data.pl_ for that:

```
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/contribute_data.pl --overwrite_locations
```

You can retrieve the central server locations (e.g. to check things went corretly):

```
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --locations
```

