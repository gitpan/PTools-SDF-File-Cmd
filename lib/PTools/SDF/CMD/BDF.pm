# -*- Perl -*-
#
# File:  PTools/SDF/CMD/BDF.pm
# Desc:  Load "/bin/bdf" output into a PTools::SDF::IDX object
# Date:  Thu Feb 13 12:49:43 2003
# Stat:  Prototype
#
# Synopsis:
#        use PTools::SDF::CMD::BDF;
#  or    use PTools::SDF::CMD::BDF 0.06 qw( lite );   # (omited from man page)
#
#        $bdfObj = new PTools::SDF::CMD::BDF;
#  or    $bdfObj = new PTools::SDF::CMD::BDF( 
#              $fsType, $matchCriteria, @fieldNames
#        );
#
# After that, it's just like using any PTools::SDF::IDX object ...
#

package PTools::SDF::CMD::BDF;
use strict;

my  $PACK = __PACKAGE__;
our $VERSION = '0.06';
our @ISA     = qw( PTools::SDF::ARRAY PTools::SDF::IDX );
                     # Inherits from PTools::SDF::SDF, too.
use PTools::SDF::ARRAY;
use PTools::SDF::IDX;

my(@validFsTypes) = qw( cdfs hfs nfs vxfs );
my(@fieldNames)   = qw(hostname filesystem kbytes used avail pctused mountedon);
my $BdfCmd;

sub import
{   my($class,@args) = @_;

    if ($args[0] and $args[0] =~ /lite|bdfl(ite)?/ and -x "/etc/scm/bdfl") {
	# UXSCM Special: "Lite" version of BDF that does not flush buffers.
	$BdfCmd = "/etc/scm/bdfl";
    } else {
	$BdfCmd = "/bin/bdf";
    }
}

sub bdfcmd { return( $BdfCmd ) }

sub new
{   my($class,$fsType,$match,@fields) = @_;

    @fields and ( @fieldNames = @fields );

    my $self = $class->SUPER::new(undef,undef,undef,@fieldNames);

    chomp(my $localHost = `hostname`);
    $self->ctrl('localHost', $localHost);

    if ($fsType !~ m#none|n\/a|skip|nobdf|no_bdf#) {

	my $result = $self->runCommand( $fsType );

	$self->parseText( $result, $match, @fieldNames );
    }

    return $self  unless wantarray;
    return($self,$self->ctrl('status'),$self->ctrl('error'));
}

*loadResult = \&parseText;
*loadText   = \&parseText;

sub parseText
{   my($self,$result,$match,@fields) = @_;

    @fields and ( @fieldNames = @fields );

    my $arrayRef = $self->parseResult( $result )   unless $self->status;

    $self->loadFile($arrayRef,$match,@fieldNames)  unless $self->status;

    return;
}

# Given an integer number for "kbytes", translate
# to either "mbytes" (2**20) or "gbytes" (2**30)
#
# If no user-defined "format pattern" was provided use a default 
# pattern of "%0.0f" which is equivalent to "no formatting."

  # Here we create some method aliases:
  *kiloToMega  = \&k2m;
  *kiloToGiga  = \&k2g;

sub k2m
{   my($self,$kbytes,$format) = @_;
    return 0 unless $kbytes =~ /\d+/;
    return sprintf( $format||"%0.0f", ($kbytes / 1024) );
}
sub k2g
{   my($self,$kbytes,$format) = @_;
    return 0 unless $kbytes =~ /\d+/;
    return sprintf( $format||"%0.0f", ($kbytes / 1048576) ); 
}

*run = \&runCommand;

sub runCommand
{   my($self,$fsType,@fileSystems) = @_;

    $fsType ||= "";
    $fsType   = "" if $fsType eq "all";

    my(@args) = ();

    if (@fileSystems) {
	push @args, @fileSystems;

    } elsif ($fsType) {

	if (! grep(/^$fsType$/, @validFsTypes) ) {

	    my $fsTypes = "'". join("', '", @validFsTypes) ."' or 'all'";

	    return $self->setErr(-1,"Expecting 'fsType' of $fsTypes")
	}

	push @args, "-t $fsType"  if $fsType;
    }

    $self->ctrl('bdfTimeStamp', time);      # Collect time command ran

    my $bdfCmd = ( $BdfCmd and -x $BdfCmd ? $BdfCmd : "/bin/bdf" );
    my $result = `$bdfCmd @args 2>&1`;      # run the 'bdf' command

    my $status = $?;

    $result and chomp $result;

    #print "-" x 72 ."\n";
    #print "DEBUG: \$? = $?\n";
    #print "DEBUG: \$@ = $@\n";
    #print "DEBUG: \$! = $!\n";
    #print "-" x 72 ."\n";

    if ($status == -1 and "$!" =~ /No child process/) {
       $status = 0;
    } elsif ($status) {
       $result ||= "Error: the 'bdf' command failed (status $status)";
    }

    $self->setErr( ($status ? ($status,$result) : (0,"")) );

    return  $result  unless wantarray;
    return( $result, $status );
}

sub parseResult
{   my($self,$result,$match) = @_;

    my $arrayRef = [];

    #die "result = '$result'\n";

    my $localHost = $self->ctrl('localHost')  ||"";    # set in "new" method

    my($hostname,$filesys,$kbytes,$used,$avail,$pctused,$mountedon);
    my($bytes,$mbytes,$gbytes,$uname,$mused,$gused,$mavail,$gavail);
    my($error);
    my($idx,$tmp) = (0,"");

    foreach (split "\n", $result) {
	#print "LINE='$_'\n";

	if ( m#^([^\s]*)$# ) {
	    #
	    # This matches PARTIAL "hostname:/filesys" or "/fileys" lines
	    #
	    $tmp = $1;

	    ($hostname, $filesys) = $tmp =~ m#^(\w*):(.*)$#;

	    $hostname ||= $localHost;
	    $filesys  ||= $tmp;

	    ($kbytes, $used, $avail, $pctused, $mountedon) = ();
	    next;

	} elsif ( m#^(\s*)(\d*)\s*(\d*)\s*(\d*)\s*(\d*)%\s*(.*)$# ) {
	    #
	    # This matches PARTIAL "kbytes used avail %used mountedon" line
	    #
	    $kbytes    = $2;
	    $used      = $3;
	    $avail     = $4;
	    $pctused   = $5;
	    $mountedon = $6;

	    die "Logic error: no 'filesystem' entry in 'bdf' output in '$PACK'"
	        unless $filesys;

	} elsif ( m#^([^\s]*)\s*(\d*)\s*(\d*)\s*(\d*)\s*(\d*)%\s*(.*)$# ) {
	    #
	    # This matches lines with ALL INFO on the same line
	    #
	    $tmp       = $1;
	    $kbytes    = $2;
	    $used      = $3;
	    $avail     = $4;
	    $pctused   = $5;
	    $mountedon = $6;

	    ($hostname, $filesys) = $tmp =~ m#^(\w*):(.*)$#;

	    $hostname ||= $localHost;
	    $filesys  ||= $tmp;

	} elsif ( m#^bdf: ([^:]*): (.*)# ) {
	    #
	    # This matches lines with errors
	    #
	    $filesys = $1;
	    $error   = $2;

	    $self->setErr(-1,"Object was unable to parse all output!");

	} else {
	    next if m#^Filesystem\s*kbytes\s*used\s*avail#;
	    $self->setErr(-1,"Object was unable to parse all output!");
	}

	$arrayRef->[$idx] = "$hostname:$filesys:$kbytes:$used:$avail";
	$arrayRef->[$idx].= ":$pctused:$mountedon";

	$idx++;
	($hostname,$filesys,$kbytes,$used,$avail,$pctused,$mountedon) = ();
    }

    return $arrayRef;
}

sub parseUname
{   my($self,$mountpoint,@patterns) = @_;
    # 
    # Given an arbitrary file system mount point, look for patterns
    # indicating that a "uname" is associated with the file system.
    #
    # If no user-defined "regular expression" pattern(s)" then we will
    # attempt to pull a $uname from the following default pattern space.
    #
    unless (@patterns) {
       push @patterns, '^/home/(.*)$';
       push @patterns, '^/nethome/(.*)$';
       push @patterns, '^/users/(.*)$';
    ## push @patterns, '^/tmp_mnt/nethome/(.*)$';    ## not by default ##
    ## push @patterns, '^/ClearCase/newview/(.*)$';  ## not by default ##
    }
    my $uname;

    foreach my $regex (@patterns) {
	last if (($uname) = $mountpoint =~ $regex);
    }
    return( $uname ||"" );
}
#_________________________
1; # Required by require()

=head1 NAME

PTools::SDF::CMD::BDF - Load '/bin/bdf' output into an PTools::SDF::IDX object

=head1 VERSION

This document describes version 0.04, released Apr, 2004.

=head1 SYNOPSIS

        use PTools::SDF::CMD::BDF;

        $bdfObj = new PTools::SDF::CMD::BDF;

   or   $bdfObj = new PTools::SDF::CMD::BDF( 
              $fsType, $matchCriteria, @fieldNames
        );

After that, the B<$bdfObj> acts just like any PTools::SDF::IDX object.


=head1 DESCRIPTION

=head2 Constructor

=over 4

=item new ( [ FStype ] [, MatchCriteria ] [, FieldNameList ] )

Collect output from the Unix I</bin/bdf> command and package it up in
an B<PTools::SDF::IDX> object for easy manipulation.

=over 4

=item FStype

When supplied the B<FStype> parameter must be one of 
'B<cdfs>', 'B<hfs>', 'B<nfs>', 'B<vxfs>' or 'B<all>'.
The default is to collect every file type in the output.

=item MatchCriteria

Perl I<regular expressions> can be used to limit the amount of
data returned by the I</bin/bdf> command. This can be used in
combination with the B<FStype> parameter or not, as desired.

=item FieldNameList

The default names for fields in objects of this class is

 hostname  filesystem  kbytes  used  avail  pctused  mountedon

Use the B<FieldNameList> parameter to supply alternate names. This
is used simply to make client scripts more 'readable' to programmers.
Just remember to supply names for all seven fields.

=back

Example:

     use PTools::SDF::CMD::BDF;

     $bdfObj = new PTools::SDF::CMD::BDF;


 or  $fsType        = "vxfs";
     $matchCriteria = "\$mountpoint =~ m#ClearCase/newview/#";
     (@fieldNames)  = qw( hostname fsdev kbytes used avail pctused mountpoint )

     $bdfObj = new PTools::SDF::CMD::BDF( $fsType, $matchCriteria, @fieldNames );

Note that in the above example, any I<FieldName> used in the B<MatchCriteria>
field ('B<mountpoint>') must match a name in the B<FieldNames> list. Otherwise 
no entries will match, and no data will be returned in the resulting object.

=back


=head2 Methods

A few additional public methods are defined here. See the various parent 
classes for examples of indexing and accessing the data contained in 
objects of this class.

=over 4

=item k2m ( Kbytes [, Format ] )

=item kiloToMega ( Kbytes [, Format ] )

=item k2g ( Kbytes [, Format ] )

=item kiloToGiga ( Kbytes [, Format ] )

These methods provide a simple conversion from the B<Kbytes> reported
by the I</bin/bdf> command into either B<MegaBytes> or B<GigaBytes>

  $kbytes = $bdfObj->param( $recNum, 'kbytes' );    # fetch total "kbytes"

  $mbytes = $bdfObj->k2m( $kbytes );

  $gbytes = $bdfObj->k2g( $kbytes );

A B<Format> string can be passed, and this is used in Perl's I<sprintf>
function to return a nicely formatted number. For example, to turn the total
file system size attribute into a GigaByte fraction to one decimal place
use the following.

  $gbytes = $bdfObj->k2g( $kbytes, "%0.1f" );


=item parseText ( Text [, MatchCriteria ] [, FieldNameList ] )

This method is used to translate output from the B</bin/bdf> program
and populate the current object and can be called directly. The B<Text>
parameter is simple lines of text and the other parameters are the
same as described in the B<new> method, above.

Example:

 $matchExp = "\$mountpoint =~ m#ClearCase/newview/#";

 if ($ARGV[0] and $ARGV[0] eq "-") {
     #
     # If arg zero is a dash, read lines of text from 
     # STDIN, assuming this is output from /bin/bdf
     #
     $bdfObj = new PTools::SDF::CMD::BDF( "no_bdf" );

     while (defined ($line = <STDIN>)) {
         $text .= $line;
     }
     $bdfObj->parseText( $text, $matchExp, @fieldNames );

 } else {
     # 
     # Otherwise, any "vxfs" entries that match the expression
     #
     $bdfObj = new PTools::SDF::CMD::BDF( $fsType, $matchExp, @fieldNames );
 }

Note that the above example passes a B<FSType> of 'B<no_bdf>' to the
B<new> method. This is used to instantiate an object without running
any B</bin/bdf> process.


=item parseUname ( MountPath [, Pattern [, Pattern ... ]] )

Given an arbitrary file system mount point, look for patterns
indicating that a "uname" is associated with the file system.

If no user-defined "regular expression" B<Pattern(s)>" then we will
attempt to pull a $uname from the following default pattern space.

  qw(  ^/home/(.*)$    ^/nethome/(.*)$    ^/users/(.*)$  );

The various patterns are matched sequentially. The first time a
match succeeds the value is returned and any subsequent patterns 
are not used. 

 $mount = $bdfObj->param( $recNum, 'mountedon' );

 $uname = $bdfObj->parseUname( $mount );

In this example, if B<$mount> equals 'B</home/janedoe>', for example, 
then B<$uname> will equal B<janedoe> as the default pattern list, 
shown above, is used here.

=back


=head1 INHERITANCE

This class inherits from the B<PTools::SDF::ARRAY> and B<PTools::SDF::IDX> 
classes. Additional methods are available via these and other parent classes.

=head1 SEE ALSO

See
L<PTools::SDF::Overview>,
L<PTools::SDF::ARRAY>, L<PTools::SDF::CSV>,  L<PTools::SDF::DB>, 
L<PTools::SDF::DIR>,   L<PTools::SDF::DSET>, L<PTools::SDF::File>,
L<PTools::SDF::IDX>,   L<PTools::SDF::INI>,  L<PTools::SDF::SDF>,
L<PTools::SDF::TAG>    L<PTools::SDF::Lock::Advisory>, 
L<PTools::SDF::Sort::Bubble>, L<PTools::SDF::Sort::Quick> and 
L<PTools::SDF::Sort::Shell>.


=head1 AUTHOR

Chris Cobb, E<lt>nospamplease@ccobb.netE<gt>

=head1 COPYRIGHT

Copyright (c) 2003-2007 by Chris Cobb. All rights reserved. 
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
