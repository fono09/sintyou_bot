#!/usr/bin/perl

use strict;
use warnings;

use utf8;

use FindBin;
use Data::Dumper;
use XML::Simple;
use Encode;
use Net::Twitter;
use AnyEvent::Twitter::Stream;
use DBD::SQLite;

our $cv = AE::cv;

chdir($FindBin::Bin);

my $xml_ref = XMLin('./settings.xml');

my $nt = Net::Twitter->new(
	consumer_key => $xml_ref->{consumer_key},
	consumer_secret => $xml_ref->{consumer_secret},
	access_token => $xml_ref->{access_token},
	access_token_secret => $xml_ref->{access_token_secret},
	ssl => 1,
);


my $ats = AnyEvent::Twitter::Stream->new(
	consumer_key => $xml_ref->{consumer_key},
	consumer_secret => $xml_ref->{consumer_secret},
	token => $xml_ref->{access_token},
	token_secret => $xml_ref->{access_token_secret},
	method =>"userstream",
	replies => "all",
	on_tweet => sub {
		my $tweet = shift;
		unless(defined($tweet->{text})){return};
		&filter($tweet);
		&update($tweet);
		&add_user($tweet);
	},
);
$cv->recv;
exit;

sub filter {

	my ($tweet) = @_;
	print Dumper $tweet->{source};

}
sub update {

	my ($tweet) = @_;

}
sub add_user {

	my ($tweet) = @_;

}

