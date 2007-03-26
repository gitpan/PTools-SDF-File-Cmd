# -*- Perl -*-
#
# File:  PTools/SDF/File/Passwd.pm
# Desc:  List of Unix system users via "/etc/passwd" or "ypcat passwd"
# Date:  Thu Aug 23 17:52:18 2001
# Stat:  Prototype
#
# Synopsis:
#        use PTools::SDF::File::Passwd;
#  or    use PTools::SDF::File::Passwd qw( passwd );  # default: /etc/passwd
#  or    use PTools::SDF::File::Passwd qw( NIS );     # alt: "ypcat passwd"
#
#  Note: Only when the NIS format of "use PTools::SDF::File::Passwd" is 
#  employed is it possible to instantiate from an array of passwd entries. 
#  When this is done, the NIS password file is not loaded.
#
#        $pwObj = new PTools::SDF::File::Passwd;
#  or    $pwObj = new PTools::SDF::File::Passwd( @arrayOfPasswdEntries );
#
#  The list of system users is, at this point, sorted in "uname" order.
#  To process each entry, for example, use something like the following.
#  Pick "$fieldName" from the "@PasswdFieldNames" list, defined below.
#
#        foreach $uname ( $pwObj->getUserList ) {
#
#            (@passwdEnt) = $pwObj->getPwent( $uname );
#  or        $passwdField = $pwObj->getPwent( $uname, $fieldName );
#
#            (@gcosEntry) = $pwObj->getGcos( $uname );
#            $gcosHashRef = $pwObj->parseGcos( @gcosEntry );
#
#  or        $gcosHashRef = $pwObj->parseGcos( $uname );
#        }
#
#  Different installations define the "gcos" field in different ways.
#  To redefine how the "gcos" field in the passwd entry is parsed,
#  simply subclass this module and override the "parseGcos" method.
#
#       (@gcosFields) = $pwObj->getGcosFieldNames;
#
#  To determine field names currently defined, use the above method.
#
#  To re-sort, simply invoke the normal PTools::SDF::SDF "sort" method. This
#  is probably not necessary. See the PTools::SDF::SDF module and the modules
#  PTools::SDF::Sort::Quick and PTools::SDF::Sort::Shell for further details 
#  on sorting.
#  (Note that "$mode" may or may not work, depending on the sorter used.)
#  Pick "$keyFieldName" from the "@PasswdFieldNames" list, defined below.
#
#        $pwObj->sort( $mode, $keyFieldName );
#
#  Note that even after resorting the "getUserList" method will
#  STILL return a list sorted in 'uname' order. To process using
#  the new sort order, walk the list sequentially. For example,
#
#        foreach $rec ( 0 .. $pwObj->param ) {
#            (@passwdEnt) = $pwObj->param($rec);
#            (@gcosEntry) = $pwObj->param($rec,'gcos');
#            $gcosHashRef = $pwObj->parseGcos( @gcosEntry );
#        }
#

package PTools::SDF::File::Passwd;
 use strict;

 my $PACK = __PACKAGE__;
 use vars qw( $VERSION @ISA $MODE );
 $VERSION = '0.06';
 @ISA     = qw( PTools::SDF::ARRAY PTools::SDF::IDX );
                     # Note multiple inheritance
 $MODE    = "PAS";

 use PTools::SDF::SDF qw( noparse );            # Note this performance boost!
 use PTools::SDF::IDX;
 use PTools::SDF::ARRAY;

 my (@PasswdFieldNames) = qw(uname passwd uid gid gcos dir shell);


# Note:
# Since inheritance relationships here are complex, the appropriate
# module is referenced for each of the method invocations herein.
# Class heirarchy is $self, PTools::SDF::ARRAY, PTools::SDF::IDX, 
# PTools::SDF::SDF and PTools::SDF::File.

sub new
{   my($class,$param,$matchCriteria) = @_;

    my($self); 
    # $param is always optional but will be either
    # . a fully qualified filename      when MODE eq "PAS"
    # . an array Ref of passwd entries  when MODE eq "NIS"
    #
    if ($MODE eq "NIS") {
	my $userRef = $param;

    	# Delay loading the data for a moment here
	#
        $self = $PACK->SUPER::new,                     # see PTools::SDF::SDF

    	# If no array reference was passed in, lookup all
    	# users currently defined in our environment.
    	#
    	$userRef ||= $self->_fetchUserData;                 # see below

        # Now we can load the correct data here
        #
        $self->loadFile($userRef,undef,@PasswdFieldNames);  # see PTools::SDF::ARRAY

    } else {
	$param ||= "/etc/passwd";
        $self = PTools::SDF::SDF->new($param,undef,undef,@PasswdFieldNames);
    }

    bless $self, ref($class)||$class;

    $self->sort(undef, 'uname');                            # see below

    return($self, $self->getUserList) if wantarray;         # see below
    return $self;
}

sub getUserList
{   my $index = $_[0]->getIndex('uname');         # see PTools::SDF::IDX
    return( sort keys %$index );
}

sub getPwent
{   my($self,$uname,$field) = @_;
    my(@pwent) = $self->index('uname',$uname,$field);   # see PTools::SDF::IDX
    return @pwent;
}

sub getAcctStat
{   my($self,$uname) = @_;
    return ($self->index('uname',$uname,'passwd') =~ /^\*/ 
	   ? "Disabled" : "Active");
}

sub acctActive
{   my($self,$uname) = @_;
    return ($self->index('uname',$uname,'passwd') =~ /^\*/ ? 0 : 1 );
}

sub acctDisabled
{   my($self,$uname) = @_;
    return ($self->index('uname',$uname,'passwd') =~ /^\*/ ? 1 : 0 );
}

sub getGcos
{   my($self,$uname) = @_;
    my(@gcos) = split(',', $self->index('uname',$uname,'gcos') ||"" );
    return @gcos;
}

sub getGcosFieldNames
{   my($self,$hRef) = @_;
    # 
    # Unless we are given a hash ref (which we will assume
    # is the result of a prior "parseGcos" call), grab the
    # gcos field from the first record in our list and run
    # the parser. Then return the resulting key fields.
    #
    unless ($hRef) {
       my $uname = $self->param(0,'uname');
       my(@gcos) = $self->getGcos($uname);
       $hRef     = $self->parseGcos( @gcos );
    }
    return(sort keys %$hRef);
}

sub parseGcos
{   my($self,@gcos) = @_;

    # Assume single param is a 'uname' value, 
    # so go ahead and do a "getGcos" as well.
    # Assume multi-param is already a 'gcos' array.
    #
    my $uname = $gcos[0];
    (@gcos) = $self->getGcos($gcos[0]) if ($#gcos == 0);

    # Default definition of the "gcos" subfields ... pick something!
    #
    my(@fieldNames) = qw( empName empLoc empPhoneWork empPhoneHome );

    my($i,$hRef)    = (0,{});
    return $hRef unless @gcos;

    map { $hRef->{$_} = $gcos[$i++] ||"" } @fieldNames;
    map { $hRef->{$_} =~ s/\&/$uname/g   } @fieldNames;

    return $hRef;
}

sub _fetchUserData
{   my($self,$matchCriteria) = @_;

    my($result,@users) = ();

    $result = `/bin/ypcat passwd 2>&1` ||'';
    chomp( $result );
    my $stat = $?; 

    $stat  or (@users) = split("\n", $result);
    $stat and $self->setError(-1,"$PACK _fetchUserData: $result");

    return \@users;
}

sub import
{   my($self,@args) = @_;
    $args[0] and $MODE = ($args[0] =~ /nis/i ? 'NIS' : "");
    return;
}


*getMode = \&mode;

sub mode
{   my($self) = @_;
    return 'NIS+'        if ($MODE eq 'NIS');
    return '/etc/passwd' if ($MODE eq 'PAS');
    return '(unknown mode)';
}

# Override the "sort" method here. We probably don't want to
# use the default sort object and, whenever we do sort, we
# have to rebuild the 'uname' index.

sub sort
{   my($self,@params) = @_;
    #
    # As the "record count" exceed about 100, the default
    # "bubble sort" slows down. Substitute another sorter.
    # Use the Shell sort? The Quick sort still won't "reverse"
    # and, up to a thousand recs or so, Shell is nearly as fast.
    # See PTools::SDF::SDF and the sort modules for further details.
    #
    # $self->extend("sort", "SDF::Sort::Shell")

    $self->extend("sort", "SDF::Sort::Quick")   # see PTools::SDF::File
	unless $self->extended("sort");

    $self->SUPER::sort(@params);                # see PTools::SDF::SDF

    # Be sure to build the index AFTER the sort step.
    #
    $self->indexInit('uname');                  # see PTools::SDF::IDX

    return;
}

# Override the "save" method here, to provide a default of
# "no headings" during the save. We probably don't need to
# allow a "force" flag here. OBTW, can pass a "fileName"
# here, or use the "$passwdObj->ctrl('fileName', $fileName)"
# method prior to invoking a save.
#
# Usage:
#         $passwdObj->save;                   # rewrite file w/o SDF headings
#  or     $passwdObj->save( "newFileName" );
#  or     $passwdObj->save( "newFileName", "default" );
#  or     $passwdObj->save( "newFileName", "custom heading string" );
#
#      
#  or     $passwdObj->ctrl('fileName', "newFileName");
#         $passwdObj->save;

sub save {
   my($self,$fileName,$heading) = @_;

   $heading ||= "";
   $heading = "" if $heading eq "default";    # allow PTools::SDF::SDF header
   $heading = "nohead" unless $heading;       # default is no SDF heading

   $self->SUPER::saveFile(undef,$fileName,$heading,undef);

   return($self->ctrl('status'),$self->ctrl('error')) if wantarray;
   return; 
}

#_________________________
1; # Required by require()

__END__

=head1 NAME

PTools::SDF::File::Passwd - Get list of users via "/etc/passwd" or "ypcat passwd"

=head1 VERSION

This document describes version 0.05, released Nov 12, 2002.

=head1 SYNOPSIS

        use PTools::SDF::File::Passwd;
  or    use PTools::SDF::File::Passwd qw( passwd );  # default: from /etc/passwd
  or    use PTools::SDF::File::Passwd qw( NIS );     # alt: via "ypcat passwd"

Note: Only when the NIS format of "use PTools::SDF::File::Passwd" is employed
is it possible to instantiate from an array of passwd entries. When
this is done, the NIS password file is not loaded.

        $pwObj = new PTools::SDF::File::Passwd;
  or    $pwObj = new PTools::SDF::File::Passwd( @arrayOfPasswdEntries );

The list of system users is, at this point, sorted in "uname" order.
To process each entry, for example, use something like the following.
Pick "$fieldName" from the "@PasswdFieldNames" list, defined below.

  foreach $uname ( $pwObj->getUserList ) {

            (@passwdEnt) = $pwObj->getPwent( $uname );
    (or)    $passwdField = $pwObj->getPwent( $uname, $fieldName );

            (@gcosEntry) = $pwObj->getGcos( $uname );
            $gcosHashRef = $pwObj->parseGcos( @gcosEntry );

    (or)    $gcosHashRef = $pwObj->parseGcos( $uname );
  }

Different installations define the "gcos" field in different ways.
To redefine how the "gcos" field in the passwd entry is parsed,
simply subclass this module and override the "parseGcos" method.

  (@gcosFields) = $pwObj->getGcosFieldNames;

To determine field names currently defined, use the above method.

To re-sort, simply invoke the normal PTools::SDF::SDF "sort" method. This
is probably not necessary. See the PTools::SDF::SDF module and the modules
SDF::Sort::Quick and PTools::SDF::Sort::Shell for further details on sorting.
(Note that "$mode" may or may not work, depending on the sorter used.)
Pick "$keyFieldName" from the "@PasswdFieldNames" list, defined below.

  $pwObj->sort( $mode, $keyFieldName );

Note that even after resorting the "getUserList" method will
STILL return a list sorted in 'uname' order. To process using
the new sort order, walk the list sequentially. For example,

  foreach $rec ( 0 .. $pwObj->param ) {
       (@passwdEnt) = $pwObj->param($rec);
       (@gcosEntry) = $pwObj->param($rec,'gcos');
       $gcosHashRef = $pwObj->parseGcos( @gcosEntry );
  }


=head1 DESCRIPTION

=head2 Constructor

=over 4

=item new

Collect a list of Unix user entries from B</etc/passwd>, an B<NIS
passwd map> or B<an array of entries> in I<passwd> format.

        use PTools::SDF::File::Passwd;
  or    use PTools::SDF::File::Passwd qw( passwd );  # default: from /etc/passwd
  or    use PTools::SDF::File::Passwd qw( NIS );     # alt: via "ypcat passwd"

Note: Only when the NIS format of "use PTools::SDF::File::Passwd" is employed
is it possible to instantiate from an array of passwd entries. When
this is done, the NIS password file is not loaded.

        $pwObj = new PTools::SDF::File::Passwd;
  or    $pwObj = new PTools::SDF::File::Passwd( @arrayOfPasswdEntries );

=back


=head2 Methods

=over 4

=item getUserList

Return a list (array) of each B<Uname> defined in the current object.
This is useful for iterating through the entire list of passwd entries.

  foreach $uname ( $pwObj->getUserList ) { . . .  }


=item getPwent ( Uname, FieldName )

Search for a particular entry from the list of passwd entries and
return the given B<FieldName> portion of the entry (if the B<Uname>
lookup was successful.

     (@passwdEnt) = $pwObj->getPwent( $uname );
 or  $passwdField = $pwObj->getPwent( $uname, $fieldName );


=item getAcctStat ( Uname )

=item acctActive ( Uname )

=item acctDisabled ( Uname )

Determine the status of a given user's passwd entry. This I<assumes> that
the first character of the B<passwd> field will be set to an asterisk
("B<*>") character to signify a disabled account.

 $acctStat = $pwObj->getAcctStat( $uname );   # returns "Active" or "Disabled"

 if ($pwObj->acctActive( $uname ))   { ... }

 if ($pwObj->acctDisabled( $uname )) { ... }

B<WARN>: If additional characters are used in the local passwd file to
indicate a disabled account, this module must be subclassed and the 
necessary methods overridden.


=item getGcos ( Uname )

Search for a particular entry from the list of passwd entries and
return the GCOS portion (if an entry is found).

 (@gcosEntry) = $pwObj->getGcos( $uname );


=item getGcosFieldNames ( [ HashRef ] )

Different installations define the "gcos" field in different ways.
Use this method to obtain a list of the field names that this module 
(or any subclasses thereof) uses to store the various components 
within the GCOS field.

 (@gcosFields) = $pwObj->getGcosFieldNames;


=item parseGcos ( { Uname | GcosEntry } )

Return a hash reference containing data parsed from the GCOS
field within a passwd entry.

Different installations define the "gcos" field in different ways.
To redefine how the "gcos" field in the passwd entry is parsed,
simply subclass this module and override the "parseGcos" method.

Examples:

 $gcosHashRef = $pwObj->parseGcos( $uname );

 (@gcosEntry) = $pwObj->getGcos( $uname );
 $gcosHashRef = $pwObj->parseGcos( @gcosEntry );


=item sort ( Params )

The B<sort> method defined in the B<PTools::SDF::SDF> class is overriden
here to ensure the B<uname> index is recreated after a sort.

The B<Params> here will vary, based on the currently loaded sort
module.


=item save

The B<save> method defined in the B<PTools::SDF::SDF> class is overriden
here to prevent rewriting the passwd file. This module implements
read only access to passwd data.

=back


=head1 INHERITANCE

This class inherits from both PTools::SDF::IDX and PTools::SDF::ARRAY. The 
PTools::SDF::ARRAY class inherits from PTools::SDF::SDF which, in turn, 
inherits from PTools::SDF::File.

=head1 SEE ALSO

For additional methods see L<PTools::SDF::IDX>, L<PTools::SDF::ARRAY>, 
L<PTools::SDF::SDF> and L<PTools::SDF::File>.

For documentation on the various sorting classes available see
L<PTools::SDF::Sort::Bubble>, L<PTools::SDF::Sort::Quick> and  
L<PTools::SDF::Sort::Shell>.


=head1 AUTHOR

Chris Cobb, E<lt>nospamplease@ccobb.netE<gt>

=head1 COPYRIGHT

Copyright (c) 2002-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
