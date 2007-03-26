#!/opt/perl5/bin/perl -w
#
# File:  PTools/SDF/File/AutoView.pm
# Desc:  Load NIS+ auto.view data into an indexable PTools::SDF::SDF object
# Date:  Thu Jan 30 10:08:57 2003
# Stat:  Prototype
#
package PTools::SDF::File::AutoView;
 use strict;

 my $PACK = __PACKAGE__;
 use vars qw( $VERSION @ISA );
 $VERSION = '0.03';
 @ISA     = qw( PTools::SDF::ARRAY PTools::SDF::IDX );
                 # Note the multiple inheritance

 use PTools::SDF::SDF qw( noparse );            # Note this performance boost!
 use PTools::SDF::ARRAY;
 use PTools::SDF::IDX;

 my (@AutoViewFieldNames) = qw(uname server homedir);

sub new
{   my($class,$mapfile,@data) = @_;

    $mapfile ||= "auto.view";

    if ($mapfile !~ m#^auto\.view#) {
	my $self = new PTools::SDF::SDF;
	$self->setErr(-1,"Expecting an 'auto.view' or 'auto.view_EXT' mapname");
	return $self;
    }
    scalar(@data) or (@data) = `/bin/ypcat -k $mapfile`;

    # auto.view entries need a tweek to format correctly.
    # E.g.:   "user1 server1:/home/&"
    #   to:   "user1:server1:/home/&"
    #
    foreach (@data) {
	chomp;                     # strip newline
        s/\s*$//;                  # strip any trailing spaces
        s/\s+/ /g;                 # ensure only one space between elems
        s/ /:/g;                   # convert spaces to field separator
    }
    my $self = new PTools::SDF::ARRAY( \@data , "","", @AutoViewFieldNames);
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

PTools::SDF::File::AutoView - Load NIS+ auto.view data into an 
indexable PTools::SDF::SDF object.

=head1 VERSION

This document describes version 0.01, released Jan 30, 2003.

=head1 DESCRIPTION

=head2 Constructor

=over 4

=item new ( [ MapFile ] [, DataList ] )

Load data from a NIS auto.view file into an object of this class.

If B<MapFile> is passed it is assumed to be a variation of
the B<auto.view> or B<auto.view_*> pattern.

If B<DataList> is passed it is assumed to be an array of entries
in auto.view file format, one line per entry. Otherwise this
module runs a "ypcat -k auto.view".

 use PTools::SDF::File::AutoView;

 $autoviewObj = new PTools::SDF::File::AutoView;

 $autoviewObj = new PTools::SDF::File::AutoView( "auto.view_cup2" );

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

 $count = $autoviewObj->countUsersOnServer( "homesvr1" );

=item countUsersByServer

This method is invoked by the B<countUsersOnServer> method upon first
use. This tallys a user count for each server in the auto.view file.

=item save

Note that the B<save> method in the B<PTools::SDF::SDF> class is overridden 
here.  This module provides read-only access to NIS AutoView data.

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
