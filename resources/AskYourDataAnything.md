# Ask Your Data Anything
## Oracle AI Database: Developer Resources

Explore ways to connect Oracle AI Database with AI assistants and agent
workflows across Google Cloud, AWS, Microsoft, and OpenAI.

This collection includes integration guides, sample code, and supporting documentation. Customers can use one or more of these experiences. Supported configurations and availability may vary by integration.

## Start here

- [Google Cloud and Gemini Enterprise](#google-cloud-and-gemini-enterprise)
- [AWS and Amazon Quick](#aws-and-amazon-quick)
- [Microsoft Foundry](#microsoft-foundry)
- [OpenAI and ChatGPT](#openai-and-chatgpt)
- [Oracle AI Database foundations](#oracle-ai-database-foundations)

## Google Cloud and Gemini Enterprise

Explore the Oracle AI Database Agent for Gemini Enterprise, including
natural-language database queries and multi-agent workflows.

### Integration guides

- [Oracle AI Database Agent on Google Cloud Marketplace](https://console.cloud.google.com/marketplace/product/oracle-public-488519/oracle-ai-db-agent)
  : Marketplace listing. Google Cloud sign-in may be required.

- [Use Oracle AI Database Agent with Gemini Enterprise](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/use-oracle-ai-database-agent-google-gemini-enterprise-application.html)
  : Oracle documentation for the integration and its prerequisites.

- [Unlocking Data Insights - Part 1](https://blogs.oracle.com/developers/unlocking-data-insights-with-the-oracle-ai-database-agent-in-gemini-enterprise-part-1)
  : Architecture, database configuration, authentication, and setup.

- [Unlocking Data Insights - Part 2](https://blogs.oracle.com/developers/unlocking-data-insights-with-the-oracle-ai-database-agent-in-gemini-enterprise-part-2)
  : Extending the integration with multi-agent workflows.

### Code and administration

- [Oracle Autonomous Database samples](https://github.com/oracle-devrel/oracle-autonomous-database-samples)
  : Sample repository referenced by the integration guides.
  Look for the `google-gemini-marketplace-agents` directory.

- [Add and manage Marketplace agents in Gemini Enterprise](https://docs.cloud.google.com/gemini/enterprise/docs/register-and-manage-marketplace-agents)
  : Google documentation for adding agents and managing user access.


## AWS and Amazon Quick

Explore the MCP integration capabilities used to connect Amazon Quick with external tools and data sources.

### Supporting documentation

- [Amazon Quick MCP integration](https://docs.aws.amazon.com/quick/latest/userguide/mcp-integration.html)
  : Connection setup, authentication requirements, and supported capabilities.

- [Integrate external tools with Amazon Quick Agents using MCP](https://aws.amazon.com/blogs/machine-learning/integrate-external-tools-with-amazon-quick-agents-using-model-context-protocol-mcp/)
  : AWS walkthrough of exposing and connecting external tools.

- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/working-database-tools-mcp-server.html)
  : Oracle documentation for managed MCP access to Oracle AI Database.

These resources explain the underlying components to enable the Oracle–Amazon Quick demo.

## Microsoft Foundry

Explore how Foundry agents can work with external agents and Oracle Database Select AI capabilities.

### Supporting documentation

- [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/agent-to-agent)
  : Microsoft guidance for invoking a remote agent through A2A.

- [Select AI Agent Framework interfaces](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-agent-interfaces.html)
  : Oracle interfaces for creating and running database agents and teams.

- [Integrate Microsoft Foundry with your applications](https://learn.microsoft.com/en-us/azure/foundry/how-to/integrate-with-other-apps)
  : Microsoft overview of application integration approaches.

The connection method and authentication configuration must match the Oracle agent deployment you are using.

## OpenAI and ChatGPT

Explore the components behind the session's Oracle AI Database plugin demo ChatGPT, an MCP connection, and OCI Database Tools MCP Server.

### Supporting documentation

- [Developer mode and MCP apps in ChatGPT](https://help.openai.com/en/articles/12584461-developer-mode-and-full-mcp-connectors-in-chatgpt)
  : OpenAI guidance on creating, testing, and managing custom MCP apps,  including workspace permissions and authentication.

- [Working with Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/working-database-tools-mcp-server.html)
  : Service overview, setup, security, and troubleshooting.

- [Tutorial: Set up a Database Tools MCP Server and integrate with an MCP client](https://docs.oracle.com/en-us/iaas/database-tools/doc/tutorial.html)
  : Oracle tutorial for configuring the server and connecting an MCP client.

- [Database Tools MCP toolsets](https://docs.oracle.com/en-us/iaas/database-tools/doc/database-tools-mcp-toolsets.html)
  : Configure the tools available to connected clients.

The session demonstrates a custom integration. These links provide the underlying setup documentation. 

## Oracle AI Database

- [About Select AI](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-about.html)
  : Natural-language SQL generation, query execution, and related capabilities.

- [Select AI Agent Framework interfaces](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-agent-interfaces.html)
  : Build agents, tools, tasks, and teams using database and Python interfaces.

- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/working-database-tools-mcp-server.html)
  : Connect compatible MCP clients to Oracle AI Database.

## Choose your first use case

1. Pick a business question and the database tables or views needed to answer it.
2. Choose the assistant or agent platform your users work in.
3. Configure the integration, database identity, and permitted tools.
4. Validate results and access permissions with representative questions.
5. Extend the workflow with additional tools or agents as needed.

---

