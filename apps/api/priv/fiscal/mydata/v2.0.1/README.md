# myDATA XML schemas v2.0.1 (ADR-243)

Official AADE schemas of the myDATA REST API, version 2.0.1, as published by
AADE and redistributed in the `aade-mydata-client` npm package (2.0.1). Tests
validate every generated `InvoicesDoc` against `InvoicesDoc-v2.0.1.xsd` with
`xmllint`; response parsing follows `response-v2.0.1.xsd`.

When AADE publishes a new version, add a sibling folder, point the tests at
it and keep the old one until no document is sent with it.
