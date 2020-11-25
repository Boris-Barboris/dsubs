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