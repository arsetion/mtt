#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::Download;

use strict;
use File::Basename;
use Data::Dumper;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use MTT::Values;
use MTT::DoCommand;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;
    $ret->{test_result} = MTT::Values::FAIL;
    my $tarball_dir = MTT::DoCommand::cwd();

    # See if we got a url in the ini section
    my $url = Value($ini, $section, "download_url");
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> Download got url: $url\n");
    my $tarball_name = basename($url);

    # Do we already have this?
    if (-f $tarball_name && !$force) {
        $ret->{result_message} = "Already have $tarball_name (did not re-download)";
        $ret->{have_new} = 0;
        $ret->{test_result} = MTT::Values::PASS;
        return $ret;
    }

    # Get the username and password if supplied
    my $username = Value($ini, $section, "download_username");
    my $password = Value($ini, $section, "download_password");

    # Do the download
    unlink($tarball_name);
    MTT::Files::http_get("$url", $username, $password);

    Abort("Could not download \"$url\" -- aborting\n")
        if (! -f $tarball_name and ! $MTT::DoCommand::no_execute);
    $ret->{have_new} = 1;

    # Get the version
    my $version = Value($ini, $section, "download_version");
    if (!defined($version)) {
        # Make a best attempt to get a version number
        # 1. Try looking for name-<number> in the basename
        if ($tarball_name =~ m/[\w-]+(\d.+)\.tar.*/) {
            $version = $1;
        } else {
            $version = $tarball_name;
        }
    }
    $ret->{version} = $version;

    # This is useful for scale testing the database
    $ret->{version} = MTT::Values::RandomString(10) 
        if ($MTT::DoCommand::no_execute);
    chomp($ret->{version});

    # now adjust the tarball name to be absolute
    $ret->{module_data}->{tarball} = "$tarball_dir/$tarball_name";
    $ret->{prepare_for_install} = __PACKAGE__ . "::PrepareForInstall";

    my $post_copy = Value($ini, $section, "post_copy");
    $ret->{module_data}->{post_copy} = $post_copy if $post_copy;

    # All done
    Debug(">> Download complete\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    # Extract the tarball
    Debug(">> Download extracting tarball to $build_dir\n");

    MTT::DoCommand::Chdir($build_dir);
    my $ret = MTT::Files::unpack_tarball($source->{module_data}->{tarball}, 1);

    # Post copy
    my $post_copy = $source->{module_data}->{post_copy};
    if ($post_copy) {

        # Run the step
        Debug("Download running post_copy command: $post_copy\n");
        my $x = MTT::DoCommand::RunStep(1, $post_copy, 3000, undef,
            undef, "post_copy");
        if ($x->{timed_out}) {
            Warning("Post-copy command timed out: $x->{result_stdout}\n");
            return undef;
        } elsif (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Post-copy command failed: $x->{result_stdout}\n");
            return undef;
        }
    }

    MTT::DoCommand::Chdir($ret);

    Debug(">> Download finished extracting tarball\n");
    return $ret;
}

1;
