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
				$nt->update("\@$cont->{source}{screen_name} フォローしました。あなたを進捗させます いつもツイートするアプリで「手動」を含むリプライをください。そのアプリからの投稿を認識します。複数アプリからもOKです。");

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

	return $epoch_second;

}
sub request_white_source {

	my ($tweet) = @_;
	my $text = $tweet->{text};
	if($text =~ /\@$bot_name/ && $text =~ /手動/){
		my $source = &source_string($tweet);
		&regist_white_source($tweet) if &source_exists==0;
	}
	return;

}
sub regist_white_source {

	my ($tweet) = @_;
	my $source = &source_string($tweet);

	$nt->update("\@$manager source: $source を許可しますか？ " . int rand $tweet->{id},{ in_reply_to_status_id => $tweet->{id} });
	my $queue=$tweet->{id};
	push(@regist_queue,$queue);

	return;
	
}
sub add_white_source {

	my ($tweet) = @_;
	my $text = $tweet->{text};
	if($text =~ /\@$bot_name/ && $text =~ /許可します/){
		while(1){

			unless(defined($tweet->{in_reply_to_status_id})){
				$nt->update("sourceの追加に失敗しました" . int rand $tweet->{id},{ in_reply_to_status_id=> $tweet->{id} });
				return;
			}else{
				$tweet = $nt->show_status($tweet->{in_reply_to_status_id});
			}
				
			my $count=0;
			foreach(@regist_queue){
				if($tweet->{in_reply_to_status_id} == $_){
					$tweet = $nt->show_status($_);
					my $source = &source_string($tweet);
					if(&source_exists($source)){
						splice(@regist_queue,$count,1);
						return;
					}
					my $sth = $dbh->prepare("insert into source values (?);");
					$sth->execute($source);
					$nt->update("\@$manager source: $source を許可しました".int rand $tweet->{id});
					splice(@regist_queue,$count,1);
					return;
				}
				$count++;
			}

		}
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
	my $time = &get_time($tweet);
	my $id = $tweet->{user}{id};

	my $sth_user_create = $dbh->prepare("insert into user values(?,?);");
	my $sth_user_update = $dbh->prepare("update user set last_update = ? where id = ?;"); 
	my $sth_user = $dbh->prepare("select * from user where id = ?;");
	$sth_user->execute($id);
	if(my $sth_ref = $sth_user->fetchrow_arrayref){
		if($time - $sth_ref->[1] > 3600*3){
			my $user = $nt->show_user($id);
			my $screen_name = $user->{screen_name};
			$nt->update("\@$screen_name 進捗どうですか？".int rand $tweet->{id},{ in_reply_to_status_id => $tweet->{id} });
		}
		$sth_user_update->execute($time,$id);
		
	}else{
	
		$sth_user_create->execute($time,$id);

	}

	return;
}
