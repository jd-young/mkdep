#!/usr/bin/perl
#
#	mkdep.pl		Creates make.dep - a list of all dependencies
#
#	Written by John Young (john@thistlesoft.com), 10 September 2002
#	Copyright (c) 2002 Thistle Software (http://www.thistlesoft.com/)
#   	Adapted from ideas from Bjorn Stenberg, SourceForge (mkdep v1.0), but this 
#   	is almost a complete re-write.
#
#	You are free to use this script for any purpose, without warranty, as long
#	as you don't charge money for it.
#
# USAGE
#	See sub 'usage' below...
#
# DESCRIPTION
#	Creates a list of dependencies for a given list of C/C++/Java files.  The 
#	dependencies are those files that included in source files with the 
#	"#include" preprocessor directive.
#
#	By default, source and header files are post-pended with...
#
#		Headers:	.h .hh .hxx .hpp .h++ .inl 
#		Source:	.c .cc .cxx .cpp .c++ .java
#
# TO-DO
#	1.   This script doesn't cope with comments or with even with simple 
#	     #if...#endif constructs, like the following...
#
#		/*
#		#include "tinky-tonk.h"
#		*/
#		#if	0
#		#include "foo-bar.h"
#		#endif
#
#		Both "tinky-tonk.h" and "foo-bar.h" would be included :-(.
#
#	2.	Create, say, -s <src-pat> to override the default source and header
#		file patterns.  This may not be necessary, since it is relatively
#		easy to find the file-pattern regex in the code and change it to suit
#		your purpose.
#	
#
# HISTORY
#	Date		By	Description
#	---------------------------------------------------------------------------
#	10-Sep-02	JY	Created
# 


use strict;

(my $scriptName = $0) =~ s/\.pl//;       	# Remove the .pl
my $version = "1.0";

sub usage
{
     print $_[0] if defined ($_[0]);
"\
\
usage:  \
     perl mkdep.pl [-qshvV] [-o <output-file>] [-i <include-dirs>] <files>...\
\
     where\
\
          <files>...               A list of source code files that are to be \
                                   scanned for dependencies.  If any of the \
                                   files in the list are prepended by '\@', \
                                   then that file is expected to have a list of\
                                   files in it.  This can include wildcards, \
                                   which is first expanded.\
\
                                   If <files> is omitted or is '-' then the \
                                   standard input is read.\
\
          -i <include-dirs>        A semi-colon, or comma delimited list of \
                                   include directories that are located outside\
                                   of the current directory tree.  You can also\
                                   specify environment variables in the usual \
                                   manner.  A favourite would be to use \
                                   '\$INCLUDE'.\
\
                                   NOTE: If there are spaces in any of the \
                                   include paths, then enclose the whole lot \
                                   in quotes.  \
\
          -o <output-file>         The name of the output file.  If this is \
                                   omitted, then the output is sent to the \
                                   standard output.\
\
          -s                       Include system files.  These are the files \
                                   that use the <> delimiters for include file\
                                   names, rather than the \"\" dilimiters.\
\
          -q                       Quiet mode.  Normally, mkdep.pl warns of \
                                   any missing include files.  This option \
                                   stops that.\
\
          -h                       Prints help (this message).\
\
          -v                       Verbose mode.  This will print out message\
                                   to standard out (if the -o option is used),\
                                   or standard error (if the -o option is not\
                                   used).\
\
          -V                       Prints out the version number.\n";
}


# Deal with the command line...
use Getopt::Std;
use vars qw ($opt_h $opt_i $opt_q $opt_o $opt_s $opt_v $opt_V);
getopts ('hi:qo:svV');
print &usage and exit (0) if $opt_h;

if ( $opt_V )
{
     print "\
     mkdep $version - A make dependencies creator utility\
     Copyright (c) 2002 Thistle Software\
     All rights reserved\
     You are free to use this in any way you want, without warranty, as long\
     as you don't charge money for it.\n";
     
     exit (0);
}

# options...
my $verbose 	= $opt_v;
my $quiet 	= $opt_q;
my $outfile 	= $opt_o;
my $incSystem 	= $opt_s;


# set up where the verbose output is going...
if ( $verbose )
{
	*VERBOSE = $outfile ? *STDOUT : *STDERR;
}


my @incDirs;
if ( $opt_i )		# parse -i arguments...
{
	print VERBOSE "Processing include directories '$opt_i'\n" if $verbose;
	my @incdirs = split /,|;/, $opt_i;

	for my $dir (@incdirs)
	{
		$dir = ExpandEnvVars ($dir);		
		push @incDirs, split /;|,/, $dir;
	}
#	unshift @incDirs, ""; 		# current dir first

	if ( $verbose )
	{
		print VERBOSE "Include paths...\n";
		for my $path (@incDirs)
		{
			print VERBOSE "   '$path'\n";
		}
	}
}

# Get the files to process
unshift (@ARGV, '-') unless @ARGV;
my @files;
for my $file (@ARGV)
{
	if ( $file eq '-' )			# take filenames from standard input
	{
		while ( <> )
		{
			chomp;
			push @files, glob ($_);
		}
	}
	else
	{
		my @globbed;
		if ( $file =~ /^@(.*)/ )
		{
			$file = $1;
			for my $f (glob ($file))
			{
				@globbed = ReadCmdFile ($f);
			}
		}
		else
		{
			@globbed = glob ($file);
		}
		
		push @files, @globbed;
	}

	if ( $verbose )
	{
		print VERBOSE "Will process...\n";
		for my $file (@files)
		{
			print VERBOSE "   $file\n";
		}
	}
}




my %DEPS;		# Hash of file against list of dependencies.  We make this 
			# global so that subroutines can refer to it to cut down on the 
			# recursive scanning time.
my %MISSING;	# A hash of MISSING files against the file from which they are
			# invoked.
my %DEFINES;   # Hash of defines.  This is to cut down on processing headers
               # that have already been read, and to eliminate circular 
               # dependencies.
my %SCANNED;   # A map of files that have already been scanned (or more 
               # importantly are being scanned - stops recursion).


print VERBOSE "Parsing source files...\n" if $verbose;
for my $file (sort @files)
{
	ScanDependencies ($file);
}

# Output the dependency file...
if ( $outfile )
{
	print VERBOSE "Creating dependency file '$outfile'...\n";
	open DEP, ">$outfile" or die "Couldn't create file '$outfile': $!\n";
}
else
{
	*DEP = *STDOUT;
}	
my $timestamp = localtime;
print DEP "# $outfile\t\tDo not edit this file!  Changes may be lost.\n";
print DEP "# Automatically generated by mkdep.pl on $timestamp\n\n";

for my $file (sort @files)
{
	if ( exists $DEPS{$file} )
	{
		# Only print out if there *are* some dependencies!
		print DEP "$file : \\\n";
		
		for my $inc ( sort @{$DEPS{$file}} )
		{
			print DEP "\t$inc \\\n";
		}
		print DEP "\n\n";
	}
}


if ( keys %MISSING )
{
	print STDERR "Files missing...\n" unless $quiet;
	print DEP    "# Files missing...\n";
	for my $dep ( sort keys %MISSING )
	{
		for my $src ( sort @{$MISSING{$dep}} )
		{
			my $warning = sprintf "%-32s from %s\n", $dep, $src;
			print STDERR "   $warning" unless $quiet;
			print DEP "#\t$warning";
		}
	}
}
close DEP;


print VERBOSE "Done!\n" if $verbose;

exit 0;


#	@files = ReadCmdFile ($cmdFile)
#
#	Reads the contents of the given command file as a list of file names, each
#	on a separate line.
#
sub ReadCmdFile
{
	my ($file) = @_;
	print VERBOSE "Reading contents of file '$file'...\n" if $verbose;
	open (FILE, "$file") or die "Cannot open file $file for reading:\n\t$0\n";
	
	my @files;
	while ( <FILE> )
	{
		chomp;
		s/^\s*(.*?)\s*$/$1/;
		push @files, $_;
	}
	close FILE;
	return @files;
}


sub ParseFile
{
     my ($file, $source) = @_;
     
	my %incs;				# Hash to store include files (and to stop dups)
	for my $line ( @$source )
	{
		chomp $line;

		# parse out filename
		if ( $line =~ /\s*[\#\.]\s*include\s+\"([^\"]*)\"/ )
		{
			my $dep = $1;

			# Attempt to find the file before blindly adding it.
			$dep = FixupPath ($file, $dep);
			if ( !-e $dep )
			{
				# Hmmm.  This file doesn't exist in the scanned file's
				# current directory.  Try finding it in other places.
				$dep = FindFile ($dep);
				
				if ( !-e $dep )
				{
					push @{$MISSING{$dep}}, $file;
					next;
				}
			}
			
			if ( !exists $incs {$dep} )
			{
				print VERBOSE "   Adding '$dep' to '$file'\n";
				$incs {$dep} = "1";
				
				for my $inc ( ScanDependencies ($dep) )
				{
					$incs {$inc} = "1";
				}
			}
		}
	}
     return keys %incs;
}


#	ScanDependencies ($file)
#
#	Scans the given file $file, and adds the list of dependencies to the global 
#	%DEPS hash.  This recurses through all the dependencies, but sneakily takes 
#	a look at the map first, to stop recursing through files that it has 
#	already scanned.
#
#	Returns the complete list of include files for the scanned file.
#
sub ScanDependencies 
{
	my ($file) = @_;

	print VERBOSE "Scanning dependencies for '$file'\n";

	# look in the file list
	if ( exists $DEPS{$file} ) 
	{
		# We've already done the work in a previous call to this method.
		# Just return.
		if ( $verbose )
		{
			print VERBOSE "   Already scanned '$file' - returning previous list...\n";
			for my $dep (sort @{$DEPS{$file}} )
			{
				print VERBOSE "      '$dep'\n";
			}
		}
		return @{$DEPS{$file}};
	}

	my @incs;
     if ( exists $SCANNED {$file} )
     {
          return @incs;
     }
	
	if ( !open FILE, $file )
	{
		warn "Couldn't open file '$file' - skipping\n";
	}
	else
	{
	     $SCANNED {$file} = 1;
		my @source = <FILE>;	# read it all at once - we recurse.
		close FILE;

	     @incs = ParseFile ($file, \@source);
		push @{$DEPS{$file}}, @incs;
	}
	
	print VERBOSE "   Finished scanning '$file'\n";

	return @incs;
}




# $path = FindFile ($file)
#
#	This searches for the given file in the sub-directories given by @incDirs,
#	and then in the sub-directories in the INCLUDE environment variable.
#
#	Returns the full path name if found, and "$file" if not found.
#
sub FindFile 
{
	my ($orig) = @_;

	# Look in the current directory first...
	my ($vol, $dir, $fname, $ext) = splitpath ($orig);
	my $file = $fname . $ext;
	if ( -e $file )
	{
		return $file;
	}

	for my $dir (@incDirs)
	{
		$dir .= '/' if $dir ne "" and $dir !~ m|/$|;
		my $path = $dir . $file;
		if ( -e $path )
		{
			return $path;
		}
	}
	
#	my @INC = split /;|,/, $ENV {"INCLUDE"};
#	for my $dir (@INC)
#	{
#		$dir .= '/' if $dir ne "" and $dir !~ m|/$|;
#		my $path = $dir . $file;
#		print VERBOSE "   searching '$path'\n";
#		if ( -e $path )
#		{
#			print VERBOSE "   found '$path'\n";
#			return $path;
#		}
#	}
	return $orig;
}



# $expanded = ExpandEnvVars ($val)
#
#	Replaces all instances of ${ENV} (or $ENV) with the appropriate environment
#	variable value.
#
#	Returns the expanded string.
#
sub ExpandEnvVars
{
	my ($val) = @_;

	# Replace $ENV_VARs with the appropriate ENV variable value.  Use \035 as
	# a substitute.
	while ( $val =~ s/(\$[\{\(]?\w+[\}\)]?)/035/ ) 
	{
		$_ = $1;
		s/[\$\{\}\(\)]//g;
		$val =~ s/035/$ENV{$_}/g;
	}
	return $val;
}



# $fixedFile = FixupPath ($parent, $inc)
#
# 	Fixes up file name of $dep according to the given parent filename.  For 
#	example...
#
#		Parent				Dep			Real filename
#		----------------------------------------------------------------------
#		"TestView.cpp"			"TestView.h" 	"TestView.h" (no change)
#		"DocView/TestView.cpp"	"../Test.h" 	"Test.h"
#		
#
sub FixupPath
{
	my ($parent, $inc) = @_;
	
	my ($vol, $dir, $file, $ext) = splitpath ($inc);
	
	if ( $dir =~ m{^\\/} )
	{
		return CanonPath ($inc);		# Absolute path - return.
	}
	
	($vol, $dir, $file, $ext) = splitpath ($parent);
	my $path = $vol . $dir . $inc;
	
	return CanonPath ($path);
}


# ($vol, $dir, $fname, $ext) = splitpath ($path);
#
#	Splits a path into the four constituent components and returns them as an
#	array.
#
#	$vol			Either the drive letter followed by a colon (:), or the UNC
#				\\server\share, or "" if not an absolute path.
#	$dir			The directory followed by a trailing slash (/).  
#	$fname		The base filename (without extension).
#	$ext			The file extension including the leading period (.). 
#
sub splitpath 
{
	my ($path) = @_;
	return ""  if !defined ($path);

	my ($vol, $dir, $fname, $ext);

	# WARNING.  Impossible to understand regex approaching...
	#
	#	Examples..
	#
	#	c:\dir1\dir2\dir3\file.ext     	=>   vol  = 'c:'
	#									dir  = '\dir1\dir2\dir3\'
	#									file = 'file'
	#									ext	= 'ext'
	#	\\server\share\dir1\dir2\file.ext 	=>	vol  = '\\server\share'
	#									dir  = '\dir1\dir2\'
	#									file = 'file'
	#									ext	= 'ext'
	#	reldir/file.ext				=>	vol	= ''
	#									dir  = 'reldir/'
	#									file = 'file'
	#									ext	= 'ext'
	#
	#	The components of the regex are explained...	
	#
	#	[\\/] means either a '\' or a '/', ie, both UNIX and DOS style dir
	#	separators are allowed.	
	#
	#		[a-zA-Z]:						=> drive letter + ':'
	#		(?:\\\\|//)[^\\/]+[\\/][^\\/]+	=> //server/share
	#		(.*[\\/])						=> anything up to the last '/'
	#		(.*)							=> the remainder (file.ext)


	if ( $path =~ m!^((?:[a-zA-Z]:|(?:\\\\|//)[^\\/]+[\\/][^\\/]+)?)(.*[\\/])?(.*)$! )
	{
		$vol = $1;
		$dir = $2;
		my $file = $3;
		if ( $file =~ /^(.*)(\..*)$/ )
		{
			$fname = $1;
			$ext = $2;
		}
		else
		{
			$fname = $file;
			$ext = "";
		}
	}

	return ($vol, $dir, $fname, $ext);
}



# $pretty = CanonPath ($ugly);
#
#	Pretties up the given $ugly path by doing the various clean-ups (see 
#	below).
#
sub CanonPath
{
	my ($path) = @_;
	my $orig = $path;		# DEBUG only
	
	# Decide which separator to use.
#	my $sep = $path =~ m{\\} || $path !~ m{/} ? '\\' : '/';
	
	$path =~ s/^([a-z]:)/\u$1/s;			# drive letter -> uppercase
	$path =~ s|/|\\|g;					# '/' -> '\'
	$path =~ s%([^\\])\\+%$1\\%g;			# xx////xx  -> xx/xx
	$path =~ s|(\\\.)+\\|\\|g;			# xx/././xx -> xx/xx
	$path =~ s|^(\.\\)+||s 				# ./xx      -> xx
				unless $path eq ".\\";  
	$path =~ s%[^\\]+\\\.\.\\%%g;			# Get rid of 'dir/../'

	return $path;
}



__END__

