# Boundary And Value Tracing

Use this when function reachability cannot establish whether a mode, field, or configuration value
has a production consumer. Choose representative public operations rather than tracing every
function.

| Boundary | Questions |
| --- | --- |
| Input ownership | Is the value user-, application-, callback-, or tool-owned? |
| Validation | Is it validated once at ownership transfer or repeatedly afterward? |
| Persistence | Which values cross files, sessions, caches, or process boundaries? |
| External work | Which function actually launches, queries, or mutates an external system? |
| Consumption | Which branch, output, or side effect changes because of the value? |

Trace beyond construction to distinguish behavioral consumption, validation or identity-only use,
persistence, public output, and operator decisions. A field that is only validated, hashed,
serialized, or tested may preserve data shape without driving production behavior. Persisted shape
can itself be a compatibility contract, including for readers outside the inspected repository.
Confirm those consumers before calling the field live or dead.

Repeated validation or hashing of application-owned immutable values can indicate a misplaced
ownership boundary. First establish whether the value can change, whether corruption must be
detected at that boundary, and whether the consumer is independently supported. Those distinctions
determine whether consolidation preserves the contract.

When adjacent layers materialize or validate substantially the same entities, trace metadata and
physical payloads separately. Compare their entity sets, persistence lifetimes, production consumers,
and independent operator decisions. If one representation exists only to be copied or converted into
the next, challenge that boundary before optimizing it. Retain a separate representation when a
supported consumer or ownership contract requires it; metadata availability need not require a second
copy of every payload.

For a family of related fields or modes, use named search patterns to build a reproducible reading
set, then classify the matches by their actual use. Lexical absence does not rule out computed
names, dynamic dispatch, generated code, native consumers, or external use; a lexical match does
not establish semantic reachability.
