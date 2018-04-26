//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"
#import "NSDate+OWS.h"
#import "OWSPrimaryStorage+messageIDs.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInteraction

+ (NSArray<TSInteraction *> *)interactionsWithTimestamp:(uint64_t)timestamp
                                                ofClass:(Class)clazz
                                        withTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(timestamp > 0);

    // Accept any interaction.
    return [self interactionsWithTimestamp:timestamp
                                    filter:^(TSInteraction *interaction) {
                                        return [interaction isKindOfClass:clazz];
                                    }
                           withTransaction:transaction];
}

+ (NSArray<TSInteraction *> *)interactionsWithTimestamp:(uint64_t)timestamp
                                                 filter:(BOOL (^_Nonnull)(TSInteraction *))filter
                                        withTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(timestamp > 0);

    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];

    [TSDatabaseSecondaryIndexes
        enumerateMessagesWithTimestamp:timestamp
                             withBlock:^(NSString *collection, NSString *key, BOOL *stop) {

                                 TSInteraction *interaction =
                                     [TSInteraction fetchObjectWithUniqueID:key transaction:transaction];
                                 if (!filter(interaction)) {
                                     return;
                                 }
                                 [interactions addObject:interaction];
                             }
                      usingTransaction:transaction];

    return [interactions copy];
}

+ (NSString *)collection {
    return @"TSInteraction";
}

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread
{
    OWSAssert(timestamp > 0);

    self = [super initWithUniqueId:nil];

    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _uniqueThreadId = thread.uniqueId;

    return self;
}

#pragma mark Thread

- (TSThread *)thread
{
    return [TSThread fetchObjectWithUniqueID:self.uniqueThreadId];
}

- (TSThread *)threadWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [TSThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];
}

- (void)touchThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSThread *thread = [TSThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];
    [thread touchWithTransaction:transaction];
}

#pragma mark Date operations

- (uint64_t)millisecondsTimestamp {
    return self.timestamp;
}

- (NSDate *)dateForSorting
{
    return [NSDate ows_dateWithMillisecondsSince1970:self.timestampForSorting];
}

- (uint64_t)timestampForSorting
{
    return self.timestamp;
}

- (NSComparisonResult)compareForSorting:(TSInteraction *)other
{
    OWSAssert(other);

    uint64_t timestamp1 = self.timestampForSorting;
    uint64_t timestamp2 = other.timestampForSorting;

    if (timestamp1 > timestamp2) {
        return NSOrderedDescending;
    } else if (timestamp1 < timestamp2) {
        return NSOrderedAscending;
    } else {
        return NSOrderedSame;
    }
}

- (OWSInteractionType)interactionType
{
    OWSFail(@"%@ unknown interaction type.", self.logTag);

    return OWSInteractionType_Unknown;
}

- (NSString *)description
{
    return [NSString
        stringWithFormat:@"%@ in thread: %@ timestamp: %tu", [super description], self.uniqueThreadId, self.timestamp];
}

- (NSString *)paymentStateText
{
    NSString *path = [[NSBundle bundleForClass:[TSInteraction class]] pathForResource:@"SignalServiceKit" ofType:@"bundle"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (!bundle) {
        bundle = [NSBundle mainBundle];
    }
    
    switch (self.paymentState) {
        case TSPaymentStateFailed:
            return [bundle localizedStringForKey:@"payment-state-failed" value:@"Failed" table:@"Localizable"];
        case TSPaymentStatePendingConfirmation:
            return [bundle localizedStringForKey:@"payment-state-requested" value:@"Requested" table:@"Localizable"];
        case TSPaymentStateRejected:
            return [bundle localizedStringForKey:@"payment-state-rejected" value:@"Rejected" table:@"Localizable"];
        case TSPaymentStateApproved:
            return [bundle localizedStringForKey:@"payment-state-approved" value:@"Approved" table:@"Localizable"];
        default:
            return @"";
    }
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    if (!self.uniqueId) {
        self.uniqueId = [OWSPrimaryStorage getAndIncrementMessageIdWithTransaction:transaction];
    }

    [super saveWithTransaction:transaction];

    TSThread *fetchedThread = [TSThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];

    [fetchedThread updateWithLastMessage:self transaction:transaction];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];

    [self touchThreadWithTransaction:transaction];
}

- (BOOL)isDynamicInteraction
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
