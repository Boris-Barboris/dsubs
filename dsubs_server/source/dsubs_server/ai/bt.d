module dsubs_server.ai.bt;


abstract class BehavourTreeNode
{
	proteted
	{
		BehavourTreeNode m_parent;
		string m_description;
	}

	final @property string description() const { return m_description; }
	final @property BehavourTreeNode parent() const { return m_parent; }

	abstract @property void parent(BehavourTreeNode rhs);

	this(string description)
	{
		m_description = description;
	}
}