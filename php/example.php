<?php

include 'SevenSegments.php';

$target = null; // default is 'http://api.7segments.com';
$token = 'd7856ba1-7baf-49aa-a9e2-8f75325e1c78';
$customer = '123456789';
$project_id = 'P1';
$ss = new SevenSegments($token, $customer, $project_id, $target);
$ss->track('b', array('a' => 'e'));
$ss->track('c', array('b' => 'f'));
$ss->track('d');
$ss->identify('987654321');
$ss->track('e');
$ss->track('f');
$ss->project('default');
$ss->track('f');
$ss->track('f');

