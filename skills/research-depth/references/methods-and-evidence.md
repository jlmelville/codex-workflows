# Choosing Methods And Evidence

Use these examples when the research question leaves the method or the validation unclear. They
illustrate evidence boundaries, not required toolkits or additional work for every investigation.

## Computational And Algorithm Research

Start from the original specification or paper, its supplements and implementation, the relevant
source revision, and representative inputs. Determine whether the question concerns mathematical
correctness, implementation fidelity, performance, or usefulness; each needs different evidence.

A numerical method may need a derivation, a trusted reference comparison, and adversarial inputs
covering its assumptions. A performance claim needs semantic equivalence plus a comparable baseline
on relevant workloads. A discovery made by tuning on one dataset needs fresh evaluation before a
generalization claim. Choose checks that bear on the actual claim rather than requiring them all.

The measured program, input provenance, configuration, and uncertainty matter. A fast microbenchmark
does not establish a whole-operation improvement, and agreement with an implementation sharing the
same defect is weak independent evidence.

## Literature And Explanatory Research

Use reviews to locate the debate; inspect original studies, definitions, methods, datasets, and
supplements for claims that decide the answer. Track whether seemingly separate accounts descend
from the same source. Compare competing explanations and the populations or conditions each covers.

For a causal question, distinguish an association from a design that identifies the proposed cause.
For an unresolved theoretical question, a derivation or counterexample may be more useful than more
citations. When direct testing is unavailable, explain which independent evidence converges, which
conflicts, and how much uncertainty remains. A reputable citation does not settle applicability.

## Exploratory And Workflow Research

When the goal is to find a promising direction, judge whether the research separates alternatives
and exposes consequential unknowns. New hypotheses are useful outputs without being confirmed facts.
Use a small discriminating prototype or observation to decide where deeper work is justified.

For a skill or workflow, source validation establishes packaging and consistency. Evidence of useful
behavior requires observing realistic tasks and their outcomes. Derive success criteria from the
user's objective before inspecting outcomes; an agent following every instruction may still fail the
task. An independently performed attempt can reveal an authoring problem, but does not alone prove
repeatability or improvement over the previous approach. Delegation still requires applicable
authorization; this skill does not itself authorize additional agents.

## Origins And Design Choices

Felix Rieseberg's [How to be more ambitious](https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/)
distinguishes changing the goal's level, deepening the work, and drawing on other fields. Its depth
prompt, together with the user-supplied Shardiban adaptation, motivates the expert-practice,
primary-material, methods, and outside-evidence brief. This skill centers depth; changing the goal
requires the user's direction, and adding a field needs a concrete contribution.

The National Academies' [Reproducibility and Replicability in Science, executive summary](https://www.nationalacademies.org/read/25303/chapter/2)
distinguishes rerunning computations with the same inputs, studying the question with new data, and
generalizing beyond the studied setting. It also emphasizes uncertainty and cumulative evidence.
These distinctions inform the limits attached to validation here; they are not a universal demand
for a new replication study.

The bounded search, stopping criteria, source-quality checks, and separation of exploration from
confirmation are design choices for making the proposed prompt usable as a recurring research
workflow. The essay and supplied tweet motivate the skill; they do not establish its effectiveness.
