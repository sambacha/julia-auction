# Module that includes all auction mechanisms
# Following A/HC/LC naming pattern

# Include all mechanism implementations
include("abstract.jl")
include("first_price.jl")
include("vickrey.jl")
include("dutch.jl")
include("english.jl")
include("augmented_uniform.jl")
include("combinatorial.jl")
include("double.jl")
include("all_pay.jl")
include("japanese.jl")
include("candle.jl")
include("penny.jl")
include("unified_interface.jl")

# Export all auction types
export AuctionMechanism, SealedBidAuction, OpenOutcryAuction

# Export specific auction types
export FirstPriceAuction, VickreyAuction, DutchAuction, EnglishAuction
export AugmentedUniformAuction, CombinatorialAuction, SealedBidDoubleAuction
export AllPayAuction, JapaneseAuction, CandleAuction, PennyAuction

# Export bid and order types
export Bid, BundleBid, Order

# Export core functions
export determineClearingPrice, allocateWinners, calculatePayments
export filterValidBids, sortBidsByPrice, sortBidsByTimestamp, resolveTiesWithRule

# Export finalization functions
export finalizeFirstPriceAuction, finalizeVickreyAuction
export finalizeDutchAuction, finalizeEnglishAuction
export finalizeAugmentedUniformAuction, finalizeCombinatorialAuction
export finalizeDoubleAuction, finalizeAllPayAuction
export finalizeJapaneseAuction, finalizeCandleAuction, finalizePennyAuction

# Export unified interface
export UnifiedAuctionConfig, StandardizedResult, AuctionFactory
export run_unified_auction, compare_auction_types
export analyze_auction_performance, recommend_auction_type