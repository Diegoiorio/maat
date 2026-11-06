'use strict';

// tape-objects.js — part of the format adapter of the benchmark (T3), next to tape-junit.py: runs ONE test file
// with the project's own tape and prints tape's object stream as JSON lines. A comment (t.comment) is a string
// row, a test is a {type: "test"} row: the two cannot be confused, as they can in TAP text.
//     node tape-objects.js <test file>          (from the package root)

var path = require('path');
var util = require('util');

var tape = require(path.resolve('node_modules', 'tape'));
var stream = tape.createStream({ objectMode: true });

function show(v) {
	return util.inspect(v, { depth: 6, breakLength: Infinity });
}

stream.on('data', function (row) {
	var out;
	if (typeof row === 'string') {
		out = { type: 'comment', text: row };
	} else if (row.type === 'assert') {
		out = {
			type: 'assert', test: row.test, id: row.id, ok: !!row.ok, skip: !!row.skip, todo: !!row.todo,
			name: row.name, operator: row.operator
		};
		if (!row.ok) {
			out.expected = show(row.expected);
			out.actual = show(row.actual);
			out.at = row.functionName || row.file ? (row.functionName || '') + ' (' + row.file + ':' + row.line + ':' + row.column + ')' : (row.at ? String(row.at) : '');
			out.stack = row.error && row.error.stack ? String(row.error.stack) : '';
		}
	} else {
		out = { type: row.type, id: row.id, name: row.name, parent: row.parent };
	}
	process.stdout.write(JSON.stringify(out) + '\n');
});

require(path.resolve(process.argv[2]));
