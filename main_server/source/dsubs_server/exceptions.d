module dsubs_server.exceptions;

class AlreadyExists: Exception 
{
	this(string msg) { super(msg); }
}