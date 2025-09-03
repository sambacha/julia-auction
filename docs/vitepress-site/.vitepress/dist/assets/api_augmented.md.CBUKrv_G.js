import{_ as a,c as n,o as i,ag as e}from"./chunks/framework.UtM2fnOC.js";const h=JSON.parse('{"title":"Augmented Uniform Price Auction API","description":"","frontmatter":{},"headers":[],"relativePath":"api/augmented.md","filePath":"api/augmented.md"}'),p={name:"api/augmented.md"};function l(t,s,c,r,o,d){return i(),n("div",null,[...s[0]||(s[0]=[e(`<h1 id="augmented-uniform-price-auction-api" tabindex="-1">Augmented Uniform Price Auction API <a class="header-anchor" href="#augmented-uniform-price-auction-api" aria-label="Permalink to &quot;Augmented Uniform Price Auction API&quot;">​</a></h1><h2 id="overview" tabindex="-1">Overview <a class="header-anchor" href="#overview" aria-label="Permalink to &quot;Overview&quot;">​</a></h2><p>This reference documents the augmented uniform price auction module.</p><p>!!! note &quot;Module Structure&quot; The module contains four components: 1. <strong>Supply Schedules</strong> - Configure elastic supply 2. <strong>Tie-Breaking</strong> - Allocate tied bids strategically 3. <strong>Auction Execution</strong> - Run auctions 4. <strong>Analysis Tools</strong> - Calculate metrics</p><h2 id="types" tabindex="-1">Types <a class="header-anchor" href="#types" aria-label="Permalink to &quot;Types&quot;">​</a></h2><h3 id="core-types" tabindex="-1">Core Types <a class="header-anchor" href="#core-types" aria-label="Permalink to &quot;Core Types&quot;">​</a></h3><ul><li><code>ElasticSupplySchedule</code> - Elastic supply configuration</li><li><code>SupplyPoint</code> - Supply point with price and quantity</li><li><code>Bid</code> - Bid structure with bidder info</li><li><code>BidAllocation</code> - Allocation result</li><li><code>AuctionConfig</code> - Auction configuration</li><li><code>AuctionResult</code> - Complete auction results</li></ul><h3 id="enumerations" tabindex="-1">Enumerations <a class="header-anchor" href="#enumerations" aria-label="Permalink to &quot;Enumerations&quot;">​</a></h3><ul><li><code>ElasticityType</code> - EXPONENTIAL, LINEAR, or LOGARITHMIC</li></ul><h3 id="tie-breaking-strategies" tabindex="-1">Tie-Breaking Strategies <a class="header-anchor" href="#tie-breaking-strategies" aria-label="Permalink to &quot;Tie-Breaking Strategies&quot;">​</a></h3><ul><li><code>TieBreakingStrategy</code> - Abstract type for tie-breaking</li><li><code>StandardTieBreaking</code> - Traditional highest-bids-first</li><li><code>AugmentedTieBreaking</code> - Advanced mechanism with quantity weighting</li></ul><h2 id="functions" tabindex="-1">Functions <a class="header-anchor" href="#functions" aria-label="Permalink to &quot;Functions&quot;">​</a></h2><h3 id="supply-schedule-management" tabindex="-1">Supply Schedule Management <a class="header-anchor" href="#supply-schedule-management" aria-label="Permalink to &quot;Supply Schedule Management&quot;">​</a></h3><ul><li><code>create_elastic_schedule</code> - Creates elastic supply schedule with parameters</li><li><code>calculate_supply_at_price</code> - Calculates supply quantity at given price</li></ul><h4 id="example-creating-custom-supply-curves" tabindex="-1">Example: Creating Custom Supply Curves <a class="header-anchor" href="#example-creating-custom-supply-curves" aria-label="Permalink to &quot;Example: Creating Custom Supply Curves&quot;">​</a></h4><div class="language-jldoctest vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">jldoctest</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>julia&gt; using AugmentedUniformPriceAuction</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; # Exponential supply curve</span></span>
<span class="line"><span>       exp_supply = create_elastic_schedule(</span></span>
<span class="line"><span>           base_quantity = 1000.0,</span></span>
<span class="line"><span>           price_floor = 20.0,</span></span>
<span class="line"><span>           price_ceiling = 80.0,</span></span>
<span class="line"><span>           elasticity_type = EXPONENTIAL,</span></span>
<span class="line"><span>           elasticity_factor = 1.5</span></span>
<span class="line"><span>       );</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; # Calculate supply at different prices</span></span>
<span class="line"><span>       supply_at_30 = calculate_supply_at_price(exp_supply, 30.0);</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; supply_at_50 = calculate_supply_at_price(exp_supply, 50.0);</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; supply_at_50 &gt; supply_at_30</span></span>
<span class="line"><span>true</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; # Linear supply for comparison</span></span>
<span class="line"><span>       lin_supply = create_elastic_schedule(</span></span>
<span class="line"><span>           base_quantity = 1000.0,</span></span>
<span class="line"><span>           price_floor = 20.0,</span></span>
<span class="line"><span>           price_ceiling = 80.0,</span></span>
<span class="line"><span>           elasticity_type = LINEAR</span></span>
<span class="line"><span>       );</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; calculate_supply_at_price(lin_supply, 50.0) &lt; supply_at_50</span></span>
<span class="line"><span>true</span></span></code></pre></div><h3 id="auction-execution" tabindex="-1">Auction Execution <a class="header-anchor" href="#auction-execution" aria-label="Permalink to &quot;Auction Execution&quot;">​</a></h3><ul><li><code>run_auction</code> - Executes complete auction with bids and configuration</li><li><code>find_clearing_price</code> - Finds market-clearing price</li><li><code>validate_bids</code> - Validates bids against auction rules</li></ul><p>!!! tip &quot;Performance Optimization&quot; For auctions with more than 10,000 bids: - Pre-sort bids by price - Use binary search for clearing price - Enable partial fills</p><h3 id="analysis-functions" tabindex="-1">Analysis Functions <a class="header-anchor" href="#analysis-functions" aria-label="Permalink to &quot;Analysis Functions&quot;">​</a></h3><ul><li><code>analyze_bid_shading</code> - Estimates strategic bid shading percentage</li><li><code>calculate_efficiency</code> - Calculates auction efficiency score</li><li><code>analyze_market_concentration</code> - Computes Herfindahl index</li><li><code>calculate_price_discovery_efficiency</code> - Measures price discovery quality</li></ul><h2 id="detailed-function-documentation" tabindex="-1">Detailed Function Documentation <a class="header-anchor" href="#detailed-function-documentation" aria-label="Permalink to &quot;Detailed Function Documentation&quot;">​</a></h2><h3 id="run-auction" tabindex="-1"><code>run_auction</code> <a class="header-anchor" href="#run-auction" aria-label="Permalink to &quot;\`run_auction\`&quot;">​</a></h3><div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">run_auction</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(bids</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">::</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Vector{Bid}</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, config</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">::</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">AuctionConfig</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-&gt;</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> AuctionResult</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">Executes an augmented uniform price auction.</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#6A737D;--shiki-dark:#6A737D;"># Arguments</span></span>
<span class="line"><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;"> \`bids::Vector{Bid}\`</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">: Collection of bids to process</span></span>
<span class="line"><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;"> \`config::AuctionConfig\`</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">: Auction configuration parameters</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#6A737D;--shiki-dark:#6A737D;"># Returns</span></span>
<span class="line"><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;"> \`AuctionResult\`</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">: Auction results with allocations and metrics</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#6A737D;--shiki-dark:#6A737D;"># Algorithm</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">1.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Validate all bids against auction rules</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">2.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Find clearing price </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">using</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> binary search</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">3.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Allocate to bids above clearing price</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">4.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Apply tie</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">breaking </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">for</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> bids at clearing price</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">5.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Calculate performance metrics</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#6A737D;--shiki-dark:#6A737D;"># Example</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">\`\`\`jldoctest auction</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; using AugmentedUniformPriceAuction</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; bids = [</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           Bid(&quot;alice&quot;, 100.0, 55.0),</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           Bid(&quot;bob&quot;, 150.0, 52.0),</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           Bid(&quot;charlie&quot;, 120.0, 52.0),  # Tie with bob</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           Bid(&quot;dave&quot;, 80.0, 48.0)</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">       ];</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; config = AuctionConfig(</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           supply_schedule = create_elastic_schedule(</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">               base_quantity = 300.0,</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">               price_floor = 40.0</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           ),</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           tie_breaking = AugmentedTieBreaking(0.7, 0.3),</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">           reserve_price = 45.0</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">       );</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; result = run_auction(bids, config);</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; result.clearing_price &gt;= 45.0  # Above reserve</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">true</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; length(result.allocations) &gt; 0</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">true</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">julia&gt; result.num_tie_breaks  # Bob and Charlie tied</span></span>
<span class="line"><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">2</span></span></code></pre></div><h1 id="performance" tabindex="-1">Performance <a class="header-anchor" href="#performance" aria-label="Permalink to &quot;Performance&quot;">​</a></h1><ul><li>Time complexity: O(n log n) for n bids</li><li>Space complexity: O(n)</li><li>Typical execution: &lt;1ms for 1000 bids</li></ul><div class="language- vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang"></span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span></span></span>
<span class="line"><span>### \`create_elastic_schedule\`</span></span>
<span class="line"><span></span></span>
<span class="line"><span>\`\`\`julia</span></span>
<span class="line"><span>create_elastic_schedule(; kwargs...) -&gt; ElasticSupplySchedule</span></span>
<span class="line"><span></span></span>
<span class="line"><span>Creates an elastic supply schedule with specified parameters.</span></span>
<span class="line"><span></span></span>
<span class="line"><span># Keyword Arguments</span></span>
<span class="line"><span>- \`base_quantity::Float64\`: Starting quantity (default: 1000.0)</span></span>
<span class="line"><span>- \`price_floor::Float64\`: Minimum price (default: 10.0)</span></span>
<span class="line"><span>- \`price_ceiling::Float64\`: Maximum price (default: 100.0)</span></span>
<span class="line"><span>- \`num_points::Int\`: Number of interpolation points (default: 10)</span></span>
<span class="line"><span>- \`elasticity_type::ElasticityType\`: EXPONENTIAL, LINEAR, or LOGARITHMIC</span></span>
<span class="line"><span>- \`elasticity_factor::Float64\`: Elasticity strength (default: 1.5)</span></span>
<span class="line"><span></span></span>
<span class="line"><span># Mathematical Models</span></span>
<span class="line"><span></span></span>
<span class="line"><span>## Exponential</span></span>
<span class="line"><span>\`\`\`math</span></span>
<span class="line"><span>S(p) = S_0 \\cdot e^{\\alpha(p - p_f)}</span></span></code></pre></div><h2 id="linear" tabindex="-1">Linear <a class="header-anchor" href="#linear" aria-label="Permalink to &quot;Linear&quot;">​</a></h2><div class="language-math vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">math</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>S(p) = S_0 \\cdot (1 + \\beta(p - p_f))</span></span></code></pre></div><h2 id="logarithmic" tabindex="-1">Logarithmic <a class="header-anchor" href="#logarithmic" aria-label="Permalink to &quot;Logarithmic&quot;">​</a></h2><div class="language-math vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">math</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>S(p) = S_0 \\cdot (1 + \\log(1 + \\gamma(p - p_f)))</span></span></code></pre></div><h1 id="example" tabindex="-1">Example <a class="header-anchor" href="#example" aria-label="Permalink to &quot;Example&quot;">​</a></h1><div class="language-jldoctest vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">jldoctest</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>julia&gt; using AugmentedUniformPriceAuction</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; schedule = create_elastic_schedule(</span></span>
<span class="line"><span>           base_quantity = 500.0,</span></span>
<span class="line"><span>           price_floor = 25.0,</span></span>
<span class="line"><span>           price_ceiling = 75.0,</span></span>
<span class="line"><span>           elasticity_type = LOGARITHMIC</span></span>
<span class="line"><span>       );</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; length(schedule.points)</span></span>
<span class="line"><span>10</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; schedule.points[1].price</span></span>
<span class="line"><span>25.0</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; schedule.points[end].price</span></span>
<span class="line"><span>75.0</span></span></code></pre></div><div class="language- vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang"></span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span></span></span>
<span class="line"><span>### \`analyze_bid_shading\`</span></span>
<span class="line"><span></span></span>
<span class="line"><span>\`\`\`julia</span></span>
<span class="line"><span>analyze_bid_shading(bids::Vector{Bid}, clearing_price::Float64) -&gt; Float64</span></span>
<span class="line"><span></span></span>
<span class="line"><span>Estimates the degree of bid shading in submitted bids.</span></span>
<span class="line"><span></span></span>
<span class="line"><span># Algorithm</span></span>
<span class="line"><span>Compares marginal bids (marked with \`is_marginal=true\`) against regular bids</span></span>
<span class="line"><span>to estimate strategic shading percentage.</span></span>
<span class="line"><span></span></span>
<span class="line"><span># Returns</span></span>
<span class="line"><span>Estimated shading percentage (0-100)</span></span>
<span class="line"><span></span></span>
<span class="line"><span># Statistical Method</span></span>
<span class="line"><span>\`\`\`math</span></span>
<span class="line"><span>\\text{Shading} = \\frac{\\bar{p}_{regular} - \\bar{p}_{marginal}}{\\bar{p}_{regular}} \\times 100</span></span></code></pre></div><h1 id="example-1" tabindex="-1">Example <a class="header-anchor" href="#example-1" aria-label="Permalink to &quot;Example&quot;">​</a></h1><div class="language-jldoctest vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">jldoctest</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>julia&gt; using AugmentedUniformPriceAuction</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; # Create bids with different shading levels</span></span>
<span class="line"><span>       bids = [</span></span>
<span class="line"><span>           Bid(&quot;b1&quot;, 10.0, 50.0, is_marginal=false),  # Regular</span></span>
<span class="line"><span>           Bid(&quot;b2&quot;, 10.0, 45.0, is_marginal=true),   # Shaded marginal</span></span>
<span class="line"><span>           Bid(&quot;b3&quot;, 10.0, 49.0, is_marginal=false),  # Regular</span></span>
<span class="line"><span>           Bid(&quot;b4&quot;, 10.0, 44.0, is_marginal=true)    # Shaded marginal</span></span>
<span class="line"><span>       ];</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; shading = analyze_bid_shading(bids, 46.0);</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; shading &gt; 0  # Detected shading</span></span>
<span class="line"><span>true</span></span>
<span class="line"><span></span></span>
<span class="line"><span>julia&gt; round(shading, digits=1)</span></span>
<span class="line"><span>10.4</span></span></code></pre></div><div class="language- vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang"></span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span></span></span>
<span class="line"><span>## Advanced Usage</span></span>
<span class="line"><span></span></span>
<span class="line"><span>### Custom Tie-Breaking Implementation</span></span>
<span class="line"><span></span></span>
<span class="line"><span>!!! example &quot;Implementing Custom Tie-Breaking&quot;</span></span>
<span class="line"><span>    \`\`\`julia</span></span>
<span class="line"><span>    struct ProbabilisticTieBreaking &lt;: TieBreakingStrategy</span></span>
<span class="line"><span>        seed::Int</span></span>
<span class="line"><span>    end</span></span>
<span class="line"><span>    </span></span>
<span class="line"><span>    function resolve_ties(bids::Vector{Bid}, quantity::Float64, </span></span>
<span class="line"><span>                         strategy::ProbabilisticTieBreaking)</span></span>
<span class="line"><span>        Random.seed!(strategy.seed)</span></span>
<span class="line"><span>        shuffled = shuffle(bids)</span></span>
<span class="line"><span>        # Allocate randomly among tied bidders</span></span>
<span class="line"><span>        return allocate_up_to_quantity(shuffled, quantity)</span></span>
<span class="line"><span>    end</span></span>
<span class="line"><span>    \`\`\`</span></span>
<span class="line"><span></span></span>
<span class="line"><span>### Performance Benchmarking</span></span>
<span class="line"><span></span></span>
<span class="line"><span>\`\`\`julia</span></span>
<span class="line"><span>using BenchmarkTools</span></span>
<span class="line"><span>using AugmentedUniformPriceAuction</span></span>
<span class="line"><span></span></span>
<span class="line"><span>function benchmark_auction_sizes()</span></span>
<span class="line"><span>    sizes = [100, 1000, 10000, 100000]</span></span>
<span class="line"><span>    results = Dict()</span></span>
<span class="line"><span>    </span></span>
<span class="line"><span>    for n in sizes</span></span>
<span class="line"><span>        bids = [Bid(&quot;b$i&quot;, rand()*100, 30+rand()*40) for i in 1:n]</span></span>
<span class="line"><span>        config = AuctionConfig(</span></span>
<span class="line"><span>            supply_schedule = create_elastic_schedule(),</span></span>
<span class="line"><span>            tie_breaking = AugmentedTieBreaking()</span></span>
<span class="line"><span>        )</span></span>
<span class="line"><span>        </span></span>
<span class="line"><span>        results[n] = @benchmark run_auction($bids, $config)</span></span>
<span class="line"><span>    end</span></span>
<span class="line"><span>    </span></span>
<span class="line"><span>    return results</span></span>
<span class="line"><span>end</span></span></code></pre></div><h3 id="error-handling" tabindex="-1">Error Handling <a class="header-anchor" href="#error-handling" aria-label="Permalink to &quot;Error Handling&quot;">​</a></h3><p>!!! warning &quot;Common Errors&quot; Input validation errors:</p><pre><code>| Error | Cause | Solution |
|:------|:------|:---------|
| \`ArgumentError(&quot;Bid quantity must be positive&quot;)\` | Negative or zero quantity | Use quantities &gt; 0 |
| \`ArgumentError(&quot;Supply schedule must be monotonically increasing&quot;)\` | Invalid supply points | Check monotonicity |
| \`ArgumentError(&quot;Weights must sum to at most 1.0&quot;)\` | Invalid weights | Sum weights ≤ 1.0 |
</code></pre><h2 id="see-also" tabindex="-1">See Also <a class="header-anchor" href="#see-also" aria-label="Permalink to &quot;See Also&quot;">​</a></h2><ul><li><a href="./../theory/bid_shading.html">Theory: Bid Shading</a></li><li><a href="./../examples/advanced.html">Examples: Advanced Features</a></li><li><a href="https://github.com/julia-auction/julia-auction" target="_blank" rel="noreferrer">GitHub Repository</a></li></ul><hr><p><em>Module Index: <code>AugmentedUniformPriceAuction</code></em></p>`,44)])])}const g=a(p,[["render",l]]);export{h as __pageData,g as default};
