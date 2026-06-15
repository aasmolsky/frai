#!/usr/bin/env php
<?php
// Frai internal shim — do not edit in user projects.

declare(strict_types=1);

$path = $argv[1] ?? null;
if ($path === null) {
    fwrite(STDERR, "Script path required\n");
    exit(1);
}

$payload = json_decode(stream_get_contents(STDIN), true);
if (!is_array($payload) || !array_key_exists('input', $payload)) {
    fwrite(STDERR, "Invalid stdin payload — expected JSON with input key\n");
    exit(1);
}

require $path;

if (!function_exists('call')) {
    fwrite(STDERR, "Script must define call(\$input): {$path}\n");
    exit(1);
}

$result = call($payload['input']);
echo json_encode($result, JSON_THROW_ON_ERROR);
