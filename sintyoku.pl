#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT,":utf8";
binmode STDERR,":utf8";

use FindBin;
chdir($FindBin::Bin);

use Data::Dumper;

use Encode;
use Net::Twitter;
use AnyEvent::Twitter::Stream;

use DBI;
our $dbh = DBI->connect("DBI:SQLite:dbname=sintyoku.db","","");
&init_table;

our $cv = AE::cv;

use XML::Simple;
my $xml_ref = XMLin('./settings.xml');

our $bot_name = 'sintyoku_bot';
our $manager = 'fono09';
our @regist_queue;

my $nt = Net::Twitter->new(
	traits => [qw/API::RESTv1_1/],
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
		&add_user($tweet);
		&add_white_source($tweet);
		&filter($tweet);

	},
);
$cv->recv;
exit;

sub init_table {

	my $sth = $dbh->prepare("select count(*) from sqlite_master where type='table' and name=?");

	$sth->execute('user');
	my $sth_ref = $sth->fetchrow_arrayref;
	if($sth_ref->[0] == 0){
		$dbh->do("create table user(
						id,
						last_update
		);");
	}


	$sth->execute('source');
	$sth_ref = $sth->fetchrow_arrayref;
	if($sth_ref->[0] == 0){
		$dbh->do("create table source(
						name
		);");
	}

	return;
}
sub add_user {

	my ($tweet) = @_;
	my $id = $tweet->{id};
	my $text = $tweet->{text};
	my $screen_name = $tweet->{user}{screen_name};
	if($text =~ /\@sintyoku_bot/ && $text =~ /(follow|フォロー|ふぉろー)/){
		if($nt->follows($screen_name,$bot_name)==0){

			$nt->follow($tweet->{user}{screen_name});
			$nt->update("\@$screen_name フォローしました。これからあなたを進捗させます。",{ in_reply_to_status_id => $tweet->{id} });
			&add_white_source($tweet);
		}else{
			$nt->update("\@$screen_name 基本的に秒速でフォロバするので、まずフォローしてください。",{ in_reply_to_status_id => $tweet->{id} });
		}
	}
	return;

}
sub source_string {

	my ($tweet) = @_;
	my $source = $tweet->{source};
	$source =~ s/<.?>//g;

	return $source;

}
sub source_exists {

	my ($source) = @_;
	my $sth = $dbh->prepare("select count(name) from source where name=?");
	$sth->execute($source);
	my $sth_ref = $sth->fetchrow_arrayref;
	return $sth_ref->[0];

}
sub request_white_source {

	my ($tweet) = @_;
	my $text = $tweet->{text};
	if($text =~ "\@$bot_name" && $text =~ /手動です/){
		my $source = &source_string($tweet);
		&regist_white_source($tweet) if &source_exists==0;
	}
	return;

}
sub regist_white_source {

	my ($tweet) = @_;
	my $source = &source_string($tweet);

	my $queue = $nt->update("\@$manager via $source を許可しますか？");
	$queue = $queue->{id};
	push(@regist_queue,$queue);

	return;
	
}
sub activate_white_source {

	my ($tweet) = @_;


	return;
}
sub filter {

	my ($tweet) = @_;
	my $source = $tweet->{source};
	$source =~ s/<.*?>//g;

	if(&source_exists){
		&update($tweet);
	}
	return;
}
sub update {

	my ($tweet) = @_;
	return;
}

