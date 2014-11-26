#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT,":utf8";
binmode STDERR,":utf8";

$SIG{'QUIT'} = \&handler;
$SIG{'KILL'} = \&handler;
$SIG{'TERM'} = \&handler;

use FindBin;
chdir($FindBin::Bin);

use Data::Dumper;

use Encode;
use Net::Twitter;
use AnyEvent::Twitter::Stream;

use HTTP::Date;

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
		print "\@$tweet->{user}{screen_name} $tweet->{text}\n";
		&request_white_source($tweet);
		&add_white_source($tweet);
		&filter($tweet);

	},
	on_event => sub {

		my $cont = shift;
		unless(defined($cont->{event})){return};

		if($cont->{event} eq "follow"){

			if($cont->{target}{screen_name} eq $bot_name){

				$nt->create_friend($cont->{source}{screen_name});
				$nt->update("\@$cont->{source}{screen_name} フォローしました。あなたを進捗させます。いつもツイートするアプリで「手動」を含むリプライをください。そのアプリからの投稿を認識します。複数アプリからもOKです。");

			}

		}

	}

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
						screen_name,
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
sub source_string {

	my ($tweet) = @_;
	my $source = $tweet->{source};
	$source =~ s/<.*?>//g;
	
	return $source;

}
sub source_exists {

	my ($source) = @_;
	my $sth = $dbh->prepare("select count(*) from source where name=?");
	$sth->execute($source);
	my $sth_ref = $sth->fetchrow_arrayref;
	return $sth_ref->[0];

}
sub get_time {

	my ($tweet) = @_;

	my $created_at = $tweet->{created_at};
	$created_at =~ s/\+0000//g;
	my $epoch_second = str2time($created_at) + 3600*3;

	print "\$epoch_second = $epoch_second\n";

	return $epoch_second;

}
sub request_white_source {

	my ($tweet) = @_;
	my $text = $tweet->{text};
	if($text =~ /\@$bot_name/ && $text =~ /手動/){
		my $source = &source_string($tweet);
		&regist_white_source($tweet) if &source_exists($source)==0;
	}
	return;

}
sub regist_white_source {

	my ($tweet) = @_;
	my $source = &source_string($tweet);

	$nt->update("\@$manager source: \n$source\n を許可しますか？ " . int rand $tweet->{id},{ in_reply_to_status_id => $tweet->{id} });

	return;
}
sub add_white_source {

	my ($tweet) = @_;
	my $text = $tweet->{text};
	my $screen_name = $tweet->{user}{screen_name};
	if($text =~ /\@$bot_name/ && $text =~ /許可/ && $text !~ /(R|Q)T/ && $screen_name eq $manager){

		unless(defined($tweet->{in_reply_to_status_id})){
			$nt->update("\@$manager sourceの追加に失敗しました" . int rand $tweet->{id},{ in_reply_to_status_id=> $tweet->{id} });
			return;
		}else{
			$tweet = $nt->show_status($tweet->{in_reply_to_status_id});
		}
			
		my @list = split(/\n/,$tweet->{text});
		my $source = $list[1];
		my $sth = $dbh->prepare("insert into source values (?);");
		$sth->execute($source);
		$nt->update("\@$manager source: $source を許可しました".int rand $tweet->{id});
		return;

	}
	return;
}
sub filter {

	my ($tweet) = @_;
	my $source = &source_string($tweet);

	if(&source_exists($source)){
		&update($tweet);
	}
	return;
}
sub update {

	my ($tweet) = @_;	
	my $id = $tweet->{user}{id};
	my $screen_name = $tweet->{user}{screen_name};
	my $time = &get_time($tweet);

	my $sth_user_create = $dbh->prepare("insert into user values(?,?,?);");
	my $sth_user_update = $dbh->prepare("update user set screen_name=?,last_update=? where id=?;"); 
	my $sth_user = $dbh->prepare("select * from user where id=?;");
	$sth_user->execute($id);

	if(my $sth_ref = $sth_user->fetchrow_arrayref){

		print "\$sth_ref : \n";
		print Dumper $sth_ref;

		if($time - $sth_ref->[2] > 3600*1){
			my $screen_name = $sth_ref->[1]; 
			$nt->update("\@$screen_name 進捗どうですか？".int rand $tweet->{id},{ in_reply_to_status_id => $tweet->{id} });
		}
		$sth_user_update->execute($screen_name,$time,$id);
		
	}else{
	
		$sth_user_create->execute($id,$screen_name,$time);

	}

	return;
}
sub handler {
	$nt->update("\@$manager 進捗botは終了します".int rand 0xffff);
	exit;
}
