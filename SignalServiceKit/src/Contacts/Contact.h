//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *
 * Contact represents relevant information related to a contact from the user's
 * contact list.
 *
 */

@class CNContact;
@class PhoneNumber;
@class SignalRecipient;
@class UIImage;
@class YapDatabaseReadTransaction;

@interface Contact : MTLModel

@property (nullable, readonly, nonatomic) NSString *firstName;
@property (nullable, readonly, nonatomic) NSString *lastName;
@property (readonly, nonatomic) NSString *fullName;
@property (readonly, nonatomic) NSString *comparableNameFirstLast;
@property (readonly, nonatomic) NSString *comparableNameLastFirst;
@property (readonly, nonatomic) NSArray<PhoneNumber *> *parsedPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *userTextPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *emails;
@property (readonly, nonatomic) NSString *uniqueId;
@property (nonatomic, readonly) BOOL isSignalContact;
#if TARGET_OS_IOS
@property (nullable, readonly, nonatomic) UIImage *image;
@property (readonly, nonatomic) int32_t recordID;
@property (nullable, nonatomic, readonly) CNContact *cnContact;
#endif // TARGET_OS_IOS

- (NSArray<SignalRecipient *> *)signalRecipientsWithTransaction:(YapDatabaseReadTransaction *)transaction;
// TODO: Remove this method.
- (NSArray<NSString *> *)textSecureIdentifiers;

#if TARGET_OS_IOS

- (instancetype)initWithContactWithFirstName:(nullable NSString *)firstName
                                 andLastName:(nullable NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
                                    andImage:(nullable UIImage *)image
                                andContactID:(int32_t)record;

- (instancetype)initWithSystemContact:(CNContact *)contact NS_AVAILABLE_IOS(9_0);

- (NSString *)nameForPhoneNumber:(NSString *)recipientId;

#endif // TARGET_OS_IOS

+ (NSComparator)comparatorSortingNamesByFirstThenLast:(BOOL)firstNameOrdering;

@end

NS_ASSUME_NONNULL_END
