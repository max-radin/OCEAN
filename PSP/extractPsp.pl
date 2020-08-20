#!/usr/bin/perl
# Copyright (C) 2020 OCEAN collaboration
#
# This file is part of the OCEAN project and distributed under the terms 
# of the University of Illinois/NCSA Open Source License. See the file 
# `License' in the root directory of the present distribution.
#
#
use strict;

use JSON::PP;
use Compress::Zlib;
use MIME::Base64;

use File::Spec::Functions;
use File::Path qw(make_path);
use Cwd 'abs_path';

if (! $ENV{"OCEAN_BIN"} ) {
  abs_path($0) =~ m/(.*)\/extractPsp\.pl/;
  $ENV{"OCEAN_BIN"} = $1;
}
my $OCEAN_BIN = $ENV{"OCEAN_BIN"};

# line returns and indents
#my $json = JSON::PP->new->pretty;
my $json = JSON::PP->new;
# Sort the keys before dumping the file
#my $enable = 1;
#$json = $json->canonical([$enable]);

my @Elements = ( 'H_', 'He', 'Li', 'Be', 'B_', 'C_', 'N_', 'O_', 'F_', 'Ne', 
     'Na', 'Mg', 'Al', 'Si', 'P_', 'S_', 'Cl', 'Ar', 'K_', 'Ca', 'Sc', 'Ti', 
     'V_', 'Cr', 'Mn', 'Fe', 'Co', 'Ni', 'Cu', 'Zn', 'Ga', 'Ge', 'As', 'Se', 
     'Br', 'Kr', 'Rb', 'Sr', 'Y_', 'Zr', 'Nb', 'Mo', 'Tc', 'Ru', 'Rh', 'Pd', 
     'Ag', 'Cd', 'In', 'Sn', 'Sb', 'Te', 'I_', 'Xe', 'Cs', 'Ba', 'La', 'Ce', 
     'Pr', 'Nd', 'Pm', 'Sm', 'Eu', 'Gd', 'Tb', 'Dy', 'Ho', 'Er', 'Tm', 'Yb', 
     'Lu', 'Hf', 'Ta', 'W_', 'Re', 'Os', 'Ir', 'Pt', 'Au', 'Hg', 'Tl', 'Pb', 
     'Bi', 'Po', 'At', 'Rn', 'Fr', 'Ra', 'Ac', 'Th', 'Pa', 'U_', 'Np', 'Pu',
     'Am', 'Cm', 'Bk', 'Cf', 'Es', 'Fm', 'Md', 'No', 'Lr', 'Rf', 'Db', 'Sg',
     'Bh', 'Hs', 'Mt' );

# Need to patch up the abinit re-run detection
unlink "psp8.pplist";
if( open( IN, "pplist" ) ) {
  exit 0 unless( <IN> =~ m/NULL/ );
}
else {
  die "Failed to open pplist\n";
}


#my $filename = $ARGV[0];
open( IN, "ppdatabase" ) or die "Failed to open ppdatabase\n$!";
my $filename = <IN>;
chomp $filename;
$filename .= ".json";
$filename = catdir( $ENV{"OCEAN_BIN"}, $filename );

my $data;

my @znucl;
my %uniquePsp;
if( open( IN, "znucl" ) )
{
  local $/ = undef;
  my $znucl = <IN>;
  $znucl =~ s/\n/ /g;
  @znucl = split ' ', $znucl;
  close IN;
} 
else {
  die "Failed to open znucl\n$!";
}
foreach my $z (@znucl)
{
  my $el = $Elements[$z-1];
  $el =~ s/_//;
  $uniquePsp{ "$z"} = $el;
}

my $pspFormat;
open( IN, "dft" ) or die "Failed to open dft\n$!";
my $dft = <IN>;
close( IN );
if( $dft =~ m/abi/i ) {
  $pspFormat = 'psp8';
} else {
  $pspFormat = 'upf';
}


if( open( my $json_stream, $filename ))
{
   local $/ = undef;
   $data = $json->decode(<$json_stream>);
   close($json_stream);
}
else
{
  die "Failed to open requested input database: $filename\n";
}

my $PspText = "--------------------------------------------\n";
$PspText .= $data->{ "dojo_info" }{ "attribution" } . "\n";
$PspText .= "Version: " . $data->{ "dojo_info" }{ "dojo_dir" } . "\n";
$PspText .= "License info: " . $data->{ "dojo_info" }{ "license" } . "\n";
if( scalar @{ $data->{ "dojo_info" }{ "citation" } } == 1 ) {
  $PspText .= "Please cite the following paper: \n";
}
else {
  $PspText .= "Please cite the following papers: \n";
}
for( my $i = 0; $i < scalar @{ $data->{ "dojo_info" }{ "citation" } }; $i++ ) {
  foreach my $key (sort(keys $data->{ "dojo_info" }{ "citation" }[ $i ]))
  {
    $PspText .= "    $key = \"" . $data->{ "dojo_info" }{ "citation" }[ $i ]{ $key } . "\"\n";
  }
}



my @basename;
my $ecut = -1;
my $ecutQuality = "normal";
my %psp;
#for( my $i = 1; $i < scalar @ARGV; $i++ )
foreach my $key (keys %uniquePsp )
{
#  my $z = $ARGV[$i];
  my $z = $uniquePsp{ $key };
  print $z . "\n";
  # set ecut
  my $e = $data->{"pseudos_metadata"}{ $z }{ "hints" }{ $ecutQuality }{ "ecut" };
  $ecut = $e if ( $e > $ecut );
    
  push @basename, $data->{"pseudos_metadata"}{ $z }{ "basename" };

  $psp{ $key } = $data->{"pseudos_metadata"}{ $z }{ "basename" };
  $psp{ $key } =~ s/\.in//;
}

#Hartree to Ryd
$ecut *= 2;
print "ECUT: $ecut\n";
if( open( IN, "ecut" ) )
{
  my $oldEcut = <IN>;
  close IN;
  if( $oldEcut < 0 )
  {
    open OUT, ">", "ecut";
    print OUT "$ecut\n";
    close OUT;
  }
  elsif( $oldEcut < $ecut ) {
    print "WARNING: Input file has ecut that is less than recommended for the psps!\n";
    print "   $oldEcut < $ecut \n";
  }
}
else {
  die "Failed to open ecut\n$!";
}

my @zsymb;
if( open( IN, "zsymb" ) )
{
  local $/ = undef;
  my $zsymb = <IN>;
  $zsymb =~ s/\n/ /g;
  @zsymb = split ' ', $zsymb;
  close IN;
}
else {
  die "Failed to open zsymb\n$!";
}
#print scalar @zsymb . "\n";
if( scalar @zsymb < scalar @znucl )
{
  @zsymb = ();
#  open OUT, ">", "zsymb";
  foreach my $z (@znucl)
  {
    my $el = $Elements[$z-1];
    $el =~ s/_//;
    push @zsymb, $el;
#    print OUT "$Elements[$z-1]\n";
  }
#  close OUT;
}

my $filename =  $data->{ "dojo_info" }{ "dojo_dir" } . ".$pspFormat.json";
$filename = catdir( $ENV{"OCEAN_BIN"}, $filename );
if( open( my $json_stream, $filename ))
{ 
  local $/ = undef;
  $data = $json->decode(<$json_stream>);
  close($json_stream);
  print "$filename parsed\n";
} 
else
{
  die "Failed to open requested psp database: $filename\n";
}

#foreach basename, then write out input, psp8, and upf
#
make_path( "psp");

foreach my $b (@basename)
{
  die "Missing pseudo $b from database $filename!\n"
    unless( defined $data->{ "pseudopotentials" }{ $b } );
#  my $input = $data->{ "pseudopotentials" }{ $b }{ "input" };
#  my $psp8 = $data->{ "pseudopotentials" }{ $b }{ "psp8" };
#  my $upf = $data->{ "pseudopotentials" }{ $b }{ "upf" };

  my $file = $b;
  $file =~ s/\.in//;
  my $outfile = catfile( 'psp', $file . ".in" );
  open OUT, ">", "$outfile";
  print OUT $data->{ "pseudopotentials" }{ $b }{ "input" };
  close OUT;

  my $b64;

  if( $pspFormat eq 'psp8' ) {
    $outfile = catfile( 'psp', $file . ".psp8");
    open OUT, ">", "$outfile";
    $b64 = $data->{ "pseudopotentials" }{ $b }{ "psp8" };
    print OUT uncompress( decode_base64( $b64 ) );
    close OUT;
  }
  elsif( $pspFormat eq 'upf' ) {
    $outfile = catfile( 'psp', $file . ".UPF");
    open OUT, ">", "$outfile";
    $b64 = $data->{ "pseudopotentials" }{ $b }{ "upf" };
    print OUT uncompress( decode_base64( $b64 ) );
    close OUT;
  }
}

$PspText .= "--------------------------------------------\n";
$PspText .= $data->{ "psp_info" }{ "attribution" };
$PspText .= "  ONCVPSP version ";
$PspText .= $data->{ "psp_info" }{ "Version" };
$PspText .= ", OCEAN mod ";
$PspText .= $data->{ "psp_info" }{ "OCEAN version" } . "\n";
$PspText .= "Please cite the following paper: \n";
for( my $i = 0; $i < scalar @{ $data->{ "psp_info" }{ "citation" } }; $i++ ) {
  foreach my $key (sort(keys $data->{ "psp_info" }{ "citation" }[ $i ]))
  {
    $PspText .= "    $key = \"" . $data->{ "psp_info" }{ "citation" }[ $i ]{ $key } . "\"\n";
  }
}
$PspText .= "--------------------------------------------\n";
print $PspText;

my $ppdir = catdir( updir(), 'Common', 'psp' );
open OUT, ">", "ppdir";
print OUT "$ppdir\n";
close OUT;


open OUT, ">", "atompp";
open AB, ">", "psp8.pplist";
open UPF, ">", "upf.pplist";
open PP, ">", "pplist";
for( my $i = 0; $i < scalar @znucl; $i++ )
{
  my $z = $znucl[$i];
  print "$z   $psp{ $z }\n";
  print AB  $psp{ $z } . ".psp8\n";
  print UPF $psp{ $z } . ".UPF\n";
  print OUT "$zsymb[$i]   0.0   $psp{ $z }.UPF\n";
  print PP $psp{ $z } . "\n";
}
close AB;
close UPF;
close OUT;
close PP;
