---
outline: deep
title: About
description: >-
  Electric Next is an experimental new approach to
  building the ElectricSQL sync engine.
---

<script setup>
import Tweet from 'vue-tweet'
</script>

<img src="/img/home/zap-with-halo.svg"
    alt="Electric zap with halo"
    class="about-zap"
/>

# A new approach to building Electric

| Authored by | Published on |
| ----------- | ------------ |
| [James Arthur](https://electric-sql.com/about/team#kyle) | 17th July 2024 |

<br /> [`electric-next`](https://github.com/electric-sql/electric-next) is an experimental new approach to building ElectricSQL.

One that's informed by the lessons learned building the [previous system](https://electric-sql.com) and inspired by new insight from [Kyle&nbsp;Mathews](https://electric-sql.com/about/team#kyle).

What started as tinkering in private now looks like the way forward for Electric. So, what it is, what's changed and what does it mean for you?


## What is `electric-next`?

[`electric-next`](https://github.com/electric-sql/electric-next) is a clean rebuild. We created a new repo at [electric-sql/electric-next](https://github.com/electric-sql/electric-next) and started by porting the absolute minimum code necessary from the previous repo.

It provides an [HTTP API](/api/http) for syncing [Shapes](https://electric-sql.com/docs/usage/data-access/shapes) of data from Postgres. This can be used directly or via [client libraries](/api/clients/js) and [connectors](/api/connectors/mobx).

It's also simple to [write your own client](/guides/write-your-own-client) in any language.

## Why build a new system?

Electric has its [heritage](https://electric-sql.com/about/team#advisors) in [distributed database research](https://electric-sql.com/docs/reference/literature).

When we started, our plan was to use this research to build a next-generation distributed database. Cockroach for the AP side of the CAP theorem. The adoption dynamics of building a new database from scratch are tough. So we pivoted to use our core technology as a replication layer for existing databases.

This gave us active-active Postgres at the edge. Which is cool. However, we kept seeing that it was more optimal to take the database-grade replication guarantees all the way into the client, rather than stopping at the cloud edge. So we built a system to sync data to the client in a way that solved the concurrency challenges with local-first software architecture.

Thus, ElectricSQL was born, as an [open source platform for building local-first software](https://electric-sql.com).

### Optimality and complexity

To go from core database replication technology to a viable solution for building local-first software, we had to build a lot of stuff. Tooling for [migrations](https://electric-sql.com/docs/usage/data-modelling/migrations), [permissions](https://electric-sql.com/docs/usage/data-modelling/permissions), [client generation](https://electric-sql.com/docs/api/cli#generate), [type-safe data access](https://electric-sql.com/docs/usage/data-access/client), [live queries](https://electric-sql.com/docs/integrations/frontend/react#uselivequery), [reactivity](https://electric-sql.com/docs/reference/architecture#reactivity), [drivers](https://electric-sql.com/docs/integrations/drivers), etc.

<figure>
  <div class="img-row">
    <div class="img-border">
      <a href="/img/previous-system/data-flow.jpg">
        <img src="/img/previous-system/data-flow.jpg"
            alt="Data flow diagramme"
        />
      </a>
    </div>
    <div class="img-border">
      <a href="/img/previous-system/schema-evolution.jpg">
        <img src="/img/previous-system/schema-evolution.jpg"
            alt="Schema evolution diagramme"
        />
      </a>
    </div>
  </div>
  <figcaption className="figure-caption text-end">
    Diagrammes illustrating data flow and schema evolution from the previous
    <a href="https://electric-sql/docs/reference/architecture" target="_blank">
      architecture&nbsp;page</a>
  </figcaption>
</figure>

Coming from a research perspective, we naturally wanted the system to be optimal. We often picked the more complex solution from the design space and, as a vertically integrated system, that solution became the only one available to use with Electric.

For example, we designed the [DDLX rule system](https://electric-sql/docs/api/ddlx) in a certain way, because we wanted authorization that supported finality of local writes. However, rules (and our rules) are only one way to do authorization in a local-first system. Many applications would be happy with a simpler solution, such as Postgres RLS or a server authoritative middleware.

These decisions not only made Electric more complex to use but also more complex to develop. Despite our best efforts, this has slowed us down and tested the patience of even the most forgiving of our early adopters.

<Tweet tweet-id="1762620966256210174"
    align="center"
    conversation="none"
    theme="dark"
/>

### Skirting the demoware trap

Many of those early adopters have also reported performance and reliability issues.

The complexity of the stack has provided a wide surface for bugs. So where we've wanted to be focusing on core features, performance and stability, we've ended up fixing issues with things like [docker networking](https://github.com/electric-sql/electric/issues/582), [migration tooling](https://github.com/electric-sql/electric/issues/668) and [client-side build tools](https://github.com/electric-sql/electric/issues/798).

The danger, articulated by [Teej](https://x.com/teej_m) in the tweet below, is building a system that demos well, with magic sync APIs but that never actually scales out reliably. Because the very features and choices that make the demo magic, prevent the system from being simple enough to be bulletproof in production.

<Tweet tweet-id="1804944389715952118"
    align="center"
    conversation="none"
    theme="dark"
/>

### Refocusing our product strategy

One of the many insights that Kyle has brought is that successful systems evolve from simple systems that work. This is Gall's law:

> “A complex system that works is invariably found to have evolved from a simple system that worked. The inverse proposition also appears to be true: A complex system designed from scratch never works and cannot be made to work. You have to start over, beginning with a working simple system.” -- [John Gall: Systemantics, how systems work, and especially how they fail](https://archive.org/details/systemanticshows00gall)

This has been echoed in conversations we've had with [Paul Copplestone](https://linkedin.com/in/paulcopplestone) at [Supabase](https://supabase.com). His approach to successfully building our type of software is to make the system incremental and composable, as reflected in the [Supabase Architecture](https://supabase.com/docs/guides/getting-started/architecture) guide's product principles:

> Supabase is composable. Even though every product works in isolation, each product on the platform needs to 10x the other products.

To make a system that's incremental and composable, we need to decouple the Electric stack. So it's not a one-size-fits-all vertical stack but, instead, more of a loosely coupled set of primitives around a smaller core.

This aligns with the principle of [Worse is Better](https://en.wikipedia.org/wiki/Worse_is_better), defined by Richard P. Gabriel:

> Software quality does not necessarily increase with functionality: there is a point where less functionality ("worse") is a preferable option ("better") in terms of practicality and usability.

Gabriel contrasts "Worse is Better" with a make the "Right Thing" approach that aims to create the optimal solution. Which sounds painfully like our ambitions to make an optimal local-first platform. Whereas moving functionality out of scope, will actually allow us to make the core better and deliver on the opportunity.

So, hopefully now our motivation is clear. We need to find a way to simplify Electric, make it more loosely coupled, bring it back to it's core and iterate on solid foundations.

That's what we've done and are trying to do with `electric-next`.


## What's changed?

### Nature of the system

In the design / nature of the system.

### Use cases

What you can use it for.

### Differentiation

What makes Electric different / special.


## Where does this leave the current/previous system?

Should you use it?

...


## Where we are in the implementation of the next system?

...

### What can you use it for already?

...

### Is there a roadmap?

...

### Can you get involved in development?

...


***

## Next steps

...

