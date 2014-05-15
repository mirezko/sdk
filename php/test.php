<?php

include 'SevenSegments.php';

$target = 'http://localhost:5001';
$token = 'd7856ba1-7baf-49aa-a9e2-8f75325e1c78';
$customer = '123456789';
$debug = true;
$ss = new SevenSegments($token, $customer, null, $target, null, $debug);
// $ss->evaluate();
$ss->track('b', array('a' => 'e'));
$ss->track('c', array('b' => 'f'));
$ss->track('d');
$ss->identify('123456789');
$ss->track('e');
$ss->track('f');
$ss->project('default');
$ss->track('f');
// $ss->evaluate();
$ss->track('f');

/*$ss = new SevenSegments($token, $customer, null, $target, new _7S_SocketTransport(), $debug);
// $ss->evaluate();
$ss->track('b', array('a' => 'e'));
$ss->track('c', array('b' => 'f'));
$ss->track('d');
$ss->identify('123456789');
$ss->track('e');
$ss->track('f');
$ss->project('default');
$ss->track('f');
// $ss->evaluate();
$ss->track('f');
*/
