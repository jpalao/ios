#!/bin/env perl

use strict;
use warnings;

=head2 INSTALL_IOS_FRAMEWORK
 
1 to install ios.framework, 0 does not perform installation
 
=cut

our $INSTALL_IOS_FRAMEWORK = $ENV{'INSTALL_IOS_FRAMEWORK'};

=pod
 
=head2 IOS_FRAMEWORK_INSTALL_PATH
 
Location for ios.framework installation
 
=cut

our $IOS_FRAMEWORK_INSTALL_PATH = $ENV{'IOS_FRAMEWORK_INSTALL_PATH'};

=pod
 
=head2 OVERWRITE_IOS_FRAMEWORK
 
When INSTALL_IOS_FRAMEWORK is set, overwrite ios.framework if it exists
 
=cut

our $OVERWRITE_IOS_FRAMEWORK = $ENV{'OVERWRITE_IOS_FRAMEWORK'};

=pod

=head2 IOS_TARGET
 
The target of this build. One of:

=item 

macosx

=item

iphoneos

=item

iphonesimulator

=item

appletvos

=item

appletvsimulator

=item

watchos

=item

watchsimulator

Default is macosx

=cut

our $IOS_TARGET = $ENV{'IOS_TARGET'};

=pod
 
=head2 IOS_BUILD_CONFIGURATION
 
Either 'Debug' or 'Release'
 
=cut

our $XCODE_BUILD_CONFIG = $ENV{'IOS_BUILD_CONFIGURATION'};

$XCODE_BUILD_CONFIG .= "-$IOS_TARGET" if $IOS_TARGET !~ /macosx/;

############################################################

$INSTALL_IOS_FRAMEWORK = 1
    if (!defined $INSTALL_IOS_FRAMEWORK || 
        !length $INSTALL_IOS_FRAMEWORK);

$IOS_FRAMEWORK_INSTALL_PATH = $ENV{HOME}."/Library/Frameworks"
    if (!defined $IOS_FRAMEWORK_INSTALL_PATH ||
        !length $IOS_FRAMEWORK_INSTALL_PATH);
    
$OVERWRITE_IOS_FRAMEWORK = 0
    if (!$OVERWRITE_IOS_FRAMEWORK);

if (! -e $IOS_FRAMEWORK_INSTALL_PATH) {
    my $framework_install_dir_create =
      system ('mkdir', '-p', $IOS_FRAMEWORK_INSTALL_PATH );
    die ("Could not create framework install directory:" .
        "$IOS_FRAMEWORK_INSTALL_PATH \nResult: $framework_install_dir_create")
      if ($framework_install_dir_create);      
}

if ($INSTALL_IOS_FRAMEWORK && $OVERWRITE_IOS_FRAMEWORK) {
    print "Removing original installation\n";
    `rm -Rf $IOS_FRAMEWORK_INSTALL_PATH/ios.framework`
}

if ($INSTALL_IOS_FRAMEWORK) {
    print "Installing ios.framework ...\n";
    my $framework_location = "Build/Products/$XCODE_BUILD_CONFIG/ios.framework";
    print `cp -vR "$framework_location" "$IOS_FRAMEWORK_INSTALL_PATH"`
}

