# -*- Perl -*-
#
# File:  Makefile.PL
# Desc:  Make the makefile for the PTools-SDF-File-Cmd distribution
# Date:  Sat Mar 24 19:42:55 2007
#
use inc::Module::Install;

name		'PTools-SDF-File-Cmd';
abstract	'Simple OO wrappers for system files and command(s)';
author		'Chris Cobb <nospamplease@ccobb.net>';
license 	'perl';
perl_version	'5.006';
version		'0.01';
##all_from	'lib/PTools/SDF/File/Mnttab.pm';
tests		't/*.t';   ##  t/*/*.t t/*/*/*.t';

# When building this distribution
#no_index	directory 	=> 'eg';
build_requires	Test::More	=> 0;

# Standard modules needed
requires	strict		=> 0;
requires	warnings	=> 0;

# Additional resources needed
# -  /bin/bdf command
# -  /etc/mnttab (or /etc/fstab)
# -  /etc/passwd (or NIS+)
# -  auto.home   (NIS+)

WriteAll();
