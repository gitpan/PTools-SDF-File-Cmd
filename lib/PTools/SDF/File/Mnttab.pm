# -*- Perl -*-
#
# File:  PTools/SDF/File/Mnttab.pm
# Desc:  Simple parser for /etc/mnttab (fstab) to find mount points for paths
# Date:  Wed Jun 06 17:29:23 2001
# Stat:  Prototype
#
# Note:  This class ISA PTools::SDF::IDX which ISA PTools::SDF::SDF class.
#        We rely on the PTools::SDF::SDF class to load the /etc/mnttab file,
#        and the PTools::SDF::IDX class to search for a mount point on a path.
#
# Synopsis:
#        use PTools::SDF::File::Mnttab;
# or     use PTools::SDF::File::Mnttab  qw( followPath );
#
#        $mntRef = new PTools::SDF::File::Mnttab;     # load /etc/mnttab
#
#    Collect data about a particular mount point
#        ($mount,$type) = $mntRef->findMountPoint("/some/dir/path");
# or     $mount         = $mntRef->findMountPoint("/some/dir/path");
#        
#    Collect data about a particular device file
#        ($mount,$type) = $mntRef->findMountDev("/dev/vg00/lvol6");
# or     $mount         = $mntRef->findMountDev("/dev/someDevice");
#        
#        ($stat,$err) = $mntRef->status;      # returns any fatal error
#
#    Report data collected via prior "findMountPoint" or "findMountDev"
#        $mntRef->mountIsLocal   and print "FS is local\n";
#        $mntRef->mountNotLocal  and print "FS is NOT local\n";
#        $mntRef->validMountPoint or print "path: no directory found\n";
#
#        $mount = $mntRef->getMountPoint;     # dir  from findMountPoint|Dev
#        $type  = $mntRef->getMountType;      # type from findMountPoint|Dev
#        $device= $mntRef->getMountDevice;    # dev  from findMountPoint|Dev
#
#    Report data currently loaded from the /etc/mnttab file
#        $i=0;
#        foreach $mount ( $mntRef->listMountPoints ) { 
#           printf(" dir %3.3d: %s\n", $i++, $mount ); 
#        }
#
# When you know that all of the paths you will work with are under the
# same root directory, include the path in the "new" method. This will
# load a subset of the /etc/mnttab file including only those entries
# where the root directory is the same. This speeds mount point lookup
# when there are hundreds of entries in the /etc/mnttab file.
#
#        $mntRef = new PTools::SDF::File::Mnttab($path);
#
# Optionally include a depth parameter to include addtional levels of
# subdirectory names in the match, thereby (potentially) loading an even
# smaller subset of mnttab entries. When a path parameter is used, the 
# default depth is one, but this is in addition to the "/" (root) dir.
#
# or     $mntRef = new PTools::SDF::File::Mnttab($path,$depth);
#
# By default, any path with relative directory components or symbolic 
# links is NOT recognized as valid. To allow these path components, add 
# the "followPath" parameter to the "use" statement, as shown above. To 
# ensure that mount points can be found, the full /etc/mnttab file is
# loaded in this case, and any "$path" and "$depth" parameters to the
# "new" method are ignored.
#
# All the other PTools::SDF::IDX and PTools::SDF::SDF methods are available here, with
# notable exception of the 'save' method. Do NOT rewrite '/etc/mnttab'
#

package PTools::SDF::File::Mnttab;
use strict;

my $PACK = __PACKAGE__;
use vars qw( $VERSION @ISA $FollowPath);
$VERSION = '0.09';
@ISA     = qw( PTools::SDF::IDX );

$FollowPath = "";              # Follow symlinks, rel paths?

# Note:  Add the "noParse" option when using the "SDF::IDX" module.
#        This makes loading a large /etc/mnttab file *much* faster,
#        as every field in every record is then not parsed for IFS
#        characters. These are/can be encoded by the PTools::SDF::SDF::save
#        method, but that won't ever happen with this file.

use Cwd;
use File::Basename;
use PTools::SDF::IDX qw( noParseIFS );           # "ISA" PTools::SDF::IDX

my $LocalFS = "\^(hfs|vxfs|cdfs|reiserfs)\$";    # "local" FS types


sub new
{   my($class,$path,$depth,$mnttab) = @_;

    $mnttab ||= "/etc/mnttab";
    my $IFS   = '\s+';         # field separator is one or more spaces
    my $match = undef;

    # We can avoid parsing the entire /etc/mnttab file by passing
    # the path in which we will search. By default only the first
    # directory element is used. Depth can be used to add elements.
    # Only load a subset when "followPath" is NOT set; both params
    # are ignored when "followPath" is set.
    #
    if ($path and ! $FollowPath ) {
        $depth = int($depth) if $depth;

	# If we have a path w/out any depth, use a simple match.
	# Otherwise we have a bit of extra work to do.
	#
        if (! $depth ) {
	    ($path) = $path =~ m#^(/[^/]*)#;         # first dir ("/somedir")

	} else {
	    my @path = $class->components( $path );
	    $depth   = $#path - $depth + 1;
	    $depth   = 0 if $depth < 0;
	    $path    = join('/', $path[$depth]);     # first n dirs ...
	}

	# If we're using match criteria to load a subset of the file,
	# be sure to always include "^/$" in the pattern. This way we
	# will include the root file system as a fallback mount point.
	#
	$match = ($path ? "\$dir =~ m#^(/\$|$path)#" : "");
    }

    # Load /etc/mnttab into an PTools::SDF::SDF format object.
    # The PTools::SDF::SDF module requires field names for accessing the
    # fields within a record. Here we invent some arbitrary names.
    # Then we load the file, or at least a subset of the file.
    #
    my @fields = qw( dev dir type opts freq pass mtime );

    my $self   = $PACK->SUPER::new($mnttab, $match, $IFS, @fields);
   
    # Is sorting necessary? Probably not but, if we do, make sure to
    # use a QuickSort object instead of the default BubbleSort object. 
    # This is more important as the records loaded exceeds about 100.
    # And remember to sort BEFORE any user-indexes are created.
    #
  ## if ($self->count > 90) {
  ##     $self->extend('sort', 'SDF::Sort::Quick');    # use QuickSort
  ## }
  ## $self->sort('dir');                               # sort on 'dir' field
    
    return $self;
}


sub import 
{   my($self,@args) = @_;
    return unless $args[0];           # will we allow symlinks, rel paths?
    $args[0] =~ /^-?(f(ollow)?|symlink)/i and $FollowPath = "true";
}

sub mountIsLocal    { return $_[0]->ctrl('_MountType') =~ /$LocalFS/   }
sub mountNotLocal   { return $_[0]->ctrl('_MountType') !~ /$LocalFS/   }
sub validMountPoint { return $_[0]->ctrl('_MountType') !~ /^\*Invalid/ }

sub getMountDevice  { return $_[0]->ctrl('_MountDevice') }     # 'dev'
sub getMountPoint   { return $_[0]->ctrl('_MountPoint')  }     # 'dir'
sub getMountType    { return $_[0]->ctrl('_MountType')   }     # 'type'
sub getMountOpts    { return $_[0]->ctrl('_MountOpts')   }     # 'opts'
sub getMountTime    { return $_[0]->ctrl('_MountTime')   }     # 'mtime'


sub listMountPoints
{   my($self,$path) = @_;
    
    # Return a list of the mount points loaded from /etc/inittab
    # (this may only be a subset of the entries in this file).
    #
    ref $self or $self = new $PACK;              # Class or object method

    # Note: $self->count is a "1" based count, 
    # while $self->param is a "0" based count
    #
    my @list;
    foreach my $i (0 .. $self->param) {
	push @list, $self->param($i, 'dir');
    }
    return @list;
} 


sub components
{   my($class,$path) = @_;

    # Create a list of each subpath component within $path
    # E.g., for path "/ClearCase/be-staging/i80/" we return
    #  qw( /ClearCase/be-staging/i80
    #      /ClearCase/be-staging
    #      /ClearCase );
    #
    if (! $FollowPath ) {
	$path =~ s#(/\./|/{2})#/#g;     # omit embedded ("/./") and ("//")
	$path =~ s#/\.?$##;             # omit trailing ("/.") and/or ("/")
    }
    my @path = $path;                   # initialize array with full path

    while ( ($path = dirname($path)) ne "/" ) {
	push @path,$path;               # add each subpath component
    }
    return @path;                       # do not include "/" (root) here.
}


sub findMountPoint
{   my($self,$path) = @_;

    # Now that $path is an optional parameter to the "new" method, 
    # this subroutine will no longer work as a "class" method.
    ## ref $self or $self = new $PACK;

    $path ||= "";

    $self->resetVars($path);

    # Resolve relative path, symlinks, etc.
    #
    my $err = "";
    my $curDir = ( $FollowPath ? getcwd : "" );  # save cwd as necessary

    if ($curDir =~ /^(.*)$/) { $curDir = $1;     # untaint $curDir
    } else { die "Error: invalid data from 'getcwd' command"; }

    if ( -d $path || -l $path ) {

	if ( -l $path and ! $FollowPath ) {
	    # Note that this test will fail if $path ends in "/."
	    # We test for this, below, when $FollowPath is not set. 
	    $err = "Symlink found in path and 'followPath' not set in '$PACK'";

	} elsif ( $path !~ m#^/# and ! $FollowPath ) {
	    $err = "Relative path used and 'followPath' not set in '$PACK'";

	} elsif ( $path =~ m#\.\.# and ! $FollowPath ) {
	    $err = "Relative path used and 'followPath' not set in '$PACK'";

	} elsif ( $FollowPath and ! chdir $path ) {    # "follow" the path
	    $err = "Can't cd to '$path' in '$PACK'";

	} elsif ( $FollowPath ) {
	    $path = getcwd;            # obtain the real directory path
	    (chdir $curDir)            # restore prior working directory
	       or $err = "Cannot restore original '$curDir' in '$PACK'";
	}
    } else {
  	$err = "Invalid path '$path' in '$PACK'";
    }
    $err and $self->setError(-2,$err);
    $err and return undef;

    # Fetch a list of all subpath components within $path
    #
    my @path = $self->components( $path );
    push @path, "/";                   # do add the root FS here!

    if ( ! $FollowPath ) {
	#
	# Note: checking $path[0] here is NOT redundant with the -l
	# test, above, since any trailing "/." may have been stripped
	# by the 'components' method. The original WOULD have passed 
	# the check, where the new value will fail the test here.
	#
	foreach (@path) {
	    if ( -l $_ ) {
		$err = "Symlink found in path and 'followPath' not set in '$PACK'";
		last;
	    }
	}
	$err and $self->setError(-2,$err);
	$err and return undef;
    }
    # Check each directory subpath component looking for a mount point.
    # An indexCount greater than zero indicates a match, but only a single 
    # match is a successful result here. Otherwise, logic here is faulty.
    #
    my $ref;
    while ( $self->indexCount('dir') == 0 ) {
	$path = (shift @path) || last;
	$ref = $self->indexInit('dir', 'dir', "=~ m#^$path\$#");
    }
    return undef unless $self->indexCount('dir') == 1;

    # The "index" method is similar to the "param" method but it uses
    # a compound record index. "@idx" includes the name of the index
    # ('dir') plus the key value for the record desired. In this case,
    # the single key from the index (of one) that we just initialized.
    # See the "SDF::IDX" class for details.
    #
    my(@idx) = ('dir', keys %$ref);     # (@idx) = (<idxName>,<value>);

    $self->setVars(@idx);
    my $type = $self->ctrl('_MountType');

    return($path, $type) if wantarray;
    return($path);
}


sub findMountDevice
{   my($self,$dev) = @_;

    $self->resetVars($dev);

    my $ref = $self->indexInit('dev', 'dev', "=~ m#^$dev\$#");

    return undef unless $self->indexCount('dev') == 1;

    my(@idx) = ('dev', keys %$ref);     # (@idx) = (<idxName>,<value>);

    $self->setVars(@idx);

    my $path = $self->ctrl('_MountPoint');
    my $type = $self->ctrl('_MountType');

    return($path, $type) if wantarray;
    return($path);
}


sub setVars
{   my($self,@idx) = @_;

 ## $self->ctrl('_MountPath',   $path);   ## now set in "resetVars()" method

    $self->ctrl('_MountDevice', $self->index(@idx, 'dev')   || "*Unknown*" );
    $self->ctrl('_MountPoint',  $self->index(@idx, 'dir')   || "*Unknown*" );
    $self->ctrl('_MountType',   $self->index(@idx, 'type')  || "*Unknown*" );
    $self->ctrl('_MountOpts',   $self->index(@idx, 'opts')  || "*Unknown*" );
    $self->ctrl('_MountFreq',   $self->index(@idx, 'freq')  || "*Unknown*" );
    $self->ctrl('_MountPass',   $self->index(@idx, 'pass')  || "*Unknown*" );
    $self->ctrl('_MountTime',   $self->index(@idx, 'mtime') || "*Unknown*" );

    return;

 #  # OBSOLETE ... the long way.
 #
 #  my $dev  = $self->index(@idx, 'dev')   || "*Unknown*";
 #  my $dir  = $self->index(@idx, 'dir')   || "*Unknown*";
 #  my $type = $self->index(@idx, 'type')  || "*Unknown*";
 #  my $opts = $self->index(@idx, 'opts')  || "*Unknown*";
 #  my $freq = $self->index(@idx, 'freq')  || "*Unknown*";
 #  my $pass = $self->index(@idx, 'pass')  || "*Unknown*";
 #  my $mtime= $self->index(@idx, 'mtime') || "*Unknown*";
 #
 ## $self->ctrl('_MountPath',   $path);   ## set in "resetVars()"
 #
 #  $self->ctrl('_MountDevice', $dev);
 #  $self->ctrl('_MountPoint',  $dir);
 #  $self->ctrl('_MountType',   $type);
 #  $self->ctrl('_MountOpts',   $opts);
 #  $self->ctrl('_MountFreq',   $freq);
 #  $self->ctrl('_MountPass',   $pass);
 #  $self->ctrl('_MountTime',   $mtime);
 #
 #  return;
}

sub resetVars
{   my($self,$path) = @_;
    #
    # Hack. Fix these with a 'ctrlDelete' method in the
    # PTools::SDF::SDF class that is similar to 'delete' method
    #
    $self->{"_MountPath"}  = $path;

    $self->{"idx_dir"}     = "";
    $self->{"_MountType"}  = "*Invalid Path*";   # assume the worst
    $self->{"_MountDevice"}= "";
    $self->{"_MountPoint"} = "";
    $self->{"_MountOpts"}  = "";
    $self->{"_MountFreq"}  = "";
    $self->{"_MountPass"}  = "";
    $self->{"_MountTime"}  = "";
    return;
}

sub save {
    # The PTools::SDF::SDF::save() method is overridden here for safety.
    # We really don't want anyone to try and write out this file.
    #
    $_[0]->setError(-1,
	"You REALLY don't want to rewrite the '/etc/mnttab' file in '$PACK'");

    return($_[0]->ctrl('status'),$_[0]->ctrl('error')) if wantarray;
    return $_[0]->ctrl('status');
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

PTools::SDF::File::Mnttab - Parser for "/etc/mnttab" (/etc/fstab) file.

=head1 VERSION

This document describes version 0.08, released October, 2004.

=head1 SYNOPSIS

         use PTools::SDF::File::Mnttab;

    or   use PTools::SDF::File::Mnttab  qw( followPath );
 
         $mntRef = new PTools::SDF::File::Mnttab;     # load /etc/mnttab
 
         ($mount,$type) = $mntRef->findMountPoint("/some/dir/path");
    or   $mount         = $mntRef->findMountPoint("/some/dir/path");
         
         ($mount,$type) = $mntRef->findMountDev("/dev/vg00/lvol6");
    or   $mount         = $mntRef->findMountDev("/dev/someDevice");
         
         ($stat,$err) = $mntRef->status;      # returns any fatal error

         $mntRef->mountIsLocal   and print "FS is local\n";
         $mntRef->mountNotLocal  and print "FS is NOT local\n";
         $mntRef->validMountPoint or print "path: no directory found\n";
 
         $mount = $mntRef->getMountPoint;     # dir  from findMountPoint|Dev
         $type  = $mntRef->getMountType;      # type from findMountPoint|Dev
         $device= $mntRef->getMountDevice;    # dev  from findMountPoint|Dev

=head1 DESCRIPTION

This class is a simple parser for the file B</etc/mnttab> on Unix systems.
It is used to easily find mount point information for various file paths.

=head2 Constructor

=over 4

=item new ( BasePath [, Depth ] )

The B<new> method loads some or all of the B</etc/mnttab> file into
an object of this class.

=over 4

=item BasePath

When you know that all of the paths you will work with are under the same 
base directory path, include this B<BasePath> in the "new" method. This 
will load a subset of the /etc/mnttab file including only those entries
where the base directory path is the same. This can speed mount point 
lookups when there are hundreds of entries in the /etc/mnttab file.

 $mntRef = new PTools::SDF::File::Mnttab( $path );

=item Depth

Optionally include a B<Depth> parameter to include addtional levels of
subdirectory names in the match, thereby (potentially) loading an even
smaller subset of mnttab entries. When a B<BasePath> parameter is used,
the default B<Depth> is one, but this is in addition to the "/" (root) dir.

 $mntRef = new PTools::SDF::File::Mnttab( $path, $depth );

=back

B<Note>: By default, any path with relative directory components or symbolic 
links is NOT recognized as valid. To allow these path components, add 
the "followPath" parameter to the "use" statement, as shown above. To 
ensure that mount points can be found, the full /etc/mnttab file is
loaded in this case, and any B<$path> and B<$depth> parameters to the
B<new> method are ignored.

=back

=head2 Methods

=over 4

=item findMountPoint ( Path )

Find the B</etc/mnttab> entry, if any, for a given file system B<Path>.

Examples:

 ($mount,$type) = $mntRef->findMountPoint("/some/dir/path");

 $mount         = $mntRef->findMountPoint("/some/dir/path");

=item findMountDevice ( Device )

Find the B</etc/mnttab> entry, if any, for a given B<Device> special file.

 ($mount,$type) = $mntRef->findMountDev("/dev/vg00/lvol6");

 $mount         = $mntRef->findMountDev("/dev/someDevice");

=item listMountPoints

Return a list of the mount points loaded from the B</etc/inittab> file.
Note that this may only be a subset of the entries in this file.

Example:

 $i=0;
 foreach $mount ( $mntRef->listMountPoints ) { 
     printf(" dir %3.3d: %s\n", $i++, $mount ); 
 }


=item getMountDevice

=item getMountPoint

=item getMountType

=item getMountOpts

=item getMountTime

These methods return data values based on the result of a prior 
call to either the B<findMountPoint> or B<findMountDevice> methods.

Examples:

 $mount = $mntRef->getMountPoint;

 $type  = $mntRef->getMountType;

 $device= $mntRef->getMountDevice;

=item mountIsLocal

=item mountNotLocal

=item validMountPoint

These methods return boolean values based on the result of a prior 
call to either the B<findMountPoint> or B<findMountDevice> methods.

Examples:

 $mntRef->mountIsLocal   and print "FS is local\n";

 $mntRef->mountNotLocal  and print "FS is NOT local\n";

 $mntRef->validMountPoint or print "path: no directory found\n";

=item save

The B<save> method is disabled in this class. You really don't want
to rewrite the B</etc/mnttab> file as currently implemented. This
would cause any comments in the file to be lost.

=back

=head1 INHERITANCE

This class inherits from PTools::SDF::SDF which in turn inherits from 
PTools::SDF::File.

=head1 SEE ALSO

For additional methods see L<PTools::SDF::SDF> and L<PTools::SDF::File>.

=head1 AUTHOR

Chris Cobb, E<lt>nospamplease@ccobb.netE<gt>

=head1 COPYRIGHT

Copyright (c) 2002-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
