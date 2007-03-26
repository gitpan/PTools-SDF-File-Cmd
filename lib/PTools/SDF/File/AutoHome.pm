#!/opt/perl5/bin/perl -w
#
# File:  PTools/SDF/File/AutoHome.pm
# Desc:  Load NIS+ auto.home data into an indexable PTools::SDF::SDF object
# Date:  Mon Aug 26 10:29:44 2002
# Stat:  Prototype
#
package PTools::SDF::File::AutoHome;
 use strict;

 my $PACK = __PACKAGE__;
 use vars qw( $VERSION @ISA );
 $VERSION = '0.04';
 @ISA     = qw( PTools::SDF::ARRAY PTools::SDF::IDX ); 
                  # Note the multiple inheritance

 use PTools::SDF::SDF qw( noparse );            # Note this performance boost!
 use PTools::SDF::ARRAY;
 use PTools::SDF::IDX;

 my (@AutoHomeFieldNames) = qw(uname quota server homedir);

sub new
{   my($class,$mapfile,@data) = @_;

    # Allow for other mapfiles, but only "auto.home" is valid for now ...
    #
    $mapfile ||= "auto.home";

    if ($mapfile !~ m#^auto\.home$#) {
	my $self = new PTools::SDF::SDF;
	$self->setErr(-1,"Expecting a mapname of 'auto.home");
	return $self;
    }
    (@data) or (@data) = `/bin/ypcat -k $mapfile`;

    # auto.home entries can vary so must normalize. 
    # E.g.:   "user1 server1:/home/&"
    #         "user2 -quota server1:/mnt/homeh1/& "
    #
    foreach (@data) {
	chomp;                     # strip newline
    	s/\s*$//;                  # strip any trailing spaces
    	s/\s+/ /g;                 # ensure only one space between elems
    	my $count = s/ /:/g;       # convert spaces to field separator
	s/:/:no:/ if $count == 1;  # if no "-quota" add a field
	s/-quota/yes/;             # convert "-quota" to "yes"
    }
    my $self = new PTools::SDF::ARRAY( \@data , "","", @AutoHomeFieldNames);
    bless $self, ref($class)||$class;

    ## $self->indexInit('uname');

    return $self;
}

sub loadFile     { $_[0]->setErr(-1,"'loadFile' method disabled in '$PACK'") }
sub _loadFileSDF { }
sub save         { $_[0]->setErr(-1,"'save' method disabled in '$PACK'") }

sub countUsersByServer
{   my($self) = @_;

    ref $self or $self = $PACK->new;
    $self->setErr(0,"");

    my $countRef = {};
    $self->ctrl('_userCount', $countRef);

    foreach my $idx ( 0 .. $self->param ) {
	$countRef->{ $self->get($idx, 'server') }++;
    }
    return $countRef;
}

sub countUsersOnServer
{   my($self,$servername) = @_;

    return undef unless $servername;

    ref $self or $self = $PACK->new;
    $self->setErr(0,"");

    my $countRef = $self->ctrl('_userCount');
    $countRef  ||= $self->countUsersByServer;

    return undef unless defined $countRef->{$servername};
    return $countRef->{$servername};
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

PTools::SDF::File::AutoHome - Load NIS+ auto.home data into indexable object.

=head1 VERSION

This document describes version 0.03, released Nov 12, 2002.

=head1 DEPENDENCIES

This module depends on the following classes.

PTools::SDF::IDX, PTools::SDF::ARRAY, PTools::SDF::SDF and PTools::SDF::File.

=head1 DESCRIPTION

=head2 Constructor

=over 4

=item new ( [ MapFile ] [, DataList ] )

Load data from a NIS auto.home file into an object of this class.

If B<MapFile> is passed it may, currently, only be 'B<auto.home>'.

If B<DataList> is passed it is assumed to be an array of entries
in auto.home file format, one line per entry. Otherwise this
module runs a "ypcat -k auto.home".

 use PTools::SDF::File::AutoHome;

 $autohomeObj = new PTools::SDF::File::AutoHome;

=back

=head2 Methods

All of the methods available in classes listed in the INHERITANCE
section, below, are available in this module. These provide for
sorting, indexing and accessing the data in objects of this class.

In addition the following two methods are defined for convenience
when the number of users on a given machine is desired.

=over 4

=item countUsersOnServer ( ServerName )

This method returns the number of users that have directories on
a given B<ServerName>.

 $count = $autohomeObj->countUsersOnServer( "homesvr1" );

=item countUsersByServer

This method is invoked by the B<countUsersOnServer> method upon first
use. This tallys a user count for each server in the auto.home file.

=item save

Note that the B<save> method in the B<PTools::SDF::SDF> class is overridden 
here.  This module provides read-only access to NIS AutoHome data.

=back

=head1 DEPENDENCIES

This module depends on the following classes.

PTools::SDF::IDX, PTools::SDF::ARRAY, PTools::SDF::SDF and PTools::SDF::File.

=head1 INHERITANCE

This class inherits from both PTools::SDF::IDX and PTools::SDF::ARRAY. The 
PTools::SDF::ARRAY class inherits from PTools::SDF::SDF which, in turn, 
inherits from PTools::SDF::File.

=head1 SEE ALSO

For additional methods see L<PTools::SDF::IDX>, L<PTools::SDF::ARRAY>, 
L<PTools::SDF::SDF> and L<PTools::SDF::File>.

=head1 AUTHOR

Chris Cobb, E<lt>nospamplease@ccobb.netE<gt>

=head1 COPYRIGHT

Copyright (c) 2002-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
