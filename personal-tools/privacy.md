---
layout: default
title: Caleb Personal Tools — Privacy
permalink: /personal-tools/privacy/
---

# Privacy and Google data use

Updated November 3, 2026.

[Caleb Personal Tools](/personal-tools/) is a private integration for Caleb
Sowers' own Gmail and Google Drive. It uses gogcli to perform tasks the
account owner requests or authorizes.

## Access and use

Depending on the task, the integration can access email messages, attachments,
mail settings, Drive files, and their metadata. Its OAuth permissions allow
mail and file changes as well as reading. Those permissions are used for
the account owner's tasks; this is not a public service for other accounts.

Google data is not sold, used for advertising, or supplied to data brokers.
Use and transfer of information received from Google APIs will adhere to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including its Limited Use requirements.

## Storage and sharing

OAuth credentials are stored in the operator's local credential store.
Requested content can be processed by the assistants and model providers the
account owner has authorized, and can appear in task outputs or conversation
history. Those providers' account settings and data policies also apply.
This integration does not operate a separate public mailbox or file database.

The retention of task outputs and conversation history depends on where the
account owner chooses to save them and the controls of the services used.
Revoking Google access stops future authorized API access; it does not itself
delete previously saved outputs or conversations.

## Control and contact

The owner can revoke the app's access in
[Google Account connections](https://myaccount.google.com/connections),
remove local credentials, and delete saved task outputs through the systems
where they were stored. Questions: [contact Caleb](mailto:caleb@polli.ai).

[Terms of use](/personal-tools/terms/)
