/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.email;

import std.array: array;
import std.process: environment, pipeProcess, Redirect, wait;
import std.parallelism: task;

import dsubs_server.common;


void sendMail(string subject, string bodyContent)
{
	string emailDest = environment.get("EMAIL_DEST");
	if (emailDest)
	{
		info("sending mail");
		void doSend()
		{
			auto pipes = pipeProcess(["/usr/bin/sendmail", "-t"], Redirect.stdin);
			scope(exit) wait(pipes.pid);
			pipes.stdin.writeln("To: " ~ emailDest);
			pipes.stdin.writeln("Subject: " ~ subject);
			pipes.stdin.writeln("");
			pipes.stdin.writeln(bodyContent);
			// a single period tells sendmail we are finished
			pipes.stdin.writeln(".");
			// but at this point sendmail might not see it, we need to flush
			pipes.stdin.flush();
			// sendmail happens to exit on ".", but sometimes you have to
			// close the file:
			pipes.stdin.close();
		}
		Globals.auxTaskPool.put(task(&doSend));
	}
}