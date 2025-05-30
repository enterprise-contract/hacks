# Provenance Recordings

The [recordings](recordings) directory provides samples of SLSA Provenance attestations. These are
useful as reference as well as to assist development.

## Using the Recordings

We can use a combination of [jq](https://jqlang.github.io/jq/) and the EC CLI to execute policy
rules defined in conforma/policy against the SLSA Provenance samples found in this repo.

In most cases, SLSA Provenance attestations are processed when evaluating an image. The EC CLI is
responsible for fetching the attestations associated with the image. Below is an alternative
workflow where the SLSA Provenance has already been retrieved (like the sample ones in this repo!).

NOTE: The process described here is not recommended for production environments. Use
`ec validate image` instead since that ensures the SLSA Provenance has been properly signed.

Use `ec validate input` to verify the SLSA Provenance attestation directly.

```bash
ec validate input --policy policy.yaml \
    --file <(
        < recordings/01-SLSA-v0-2-Pipeline-in-cluster/attestation.json
        jq '{"attestations": [{"statement": .}]}')
```

The important part of the command above is that it wraps the attestation into the
[policy input](https://enterprisecontract.dev/docs/ec-cli/main/policy_input.html) format used by the
`ec validate image` command. This allows `release` policy rules to be used with the `validate input`
command.

The snippet above leverages bash features to create a throwaway file. This is useful for one-liners,
but it can quickly become cumbersome. We can split those steps instead.

```bash
< recordings/01-SLSA-v0-2-Pipeline-in-cluster/attestation.json \
    jq '{"attestations": [{"statement": .}]}' > input.json

ec validate input --policy policy.yaml --file input.json
```

It may also be desirable to modify certain attributes of the SLSA Provenance to trigger violations,
for example. This is particularly tricky with the v1.0 SLSA Provenance samples since some of the
fields are encoded in Base 64. Below is an example of how to make such a change.

```bash
< recordings/05-SLSA-v1-0-tekton-build-type-Pipeline-in-cluster/attestation.json \
    jq '.predicate.buildDefinition.resolvedDependencies[0].content |=
        (@base64d | fromjson | .spec.taskRef.params[1].value |= "main" | @base64)' | \
    jq '{"attestations": [{"statement": .}]}' > input.json

ec validate input --policy policy.yaml --file input.json --output json
```

The content of the first Task is updated so the second parameter (`revision`) for the `git` resolver
is updated with the value of `"main"`. For the sake of simplicity, it assumes the Task and the
resolver parameters are at a specific location.

The two `jq` commands could be combined into one, but hopefully this makes it easier to understand.
