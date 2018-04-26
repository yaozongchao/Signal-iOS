//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GroupUpdateTypeSting;
extern NSString *const GroupInfoString;

extern NSString *const GroupCreateMessage;
extern NSString *const GroupBecameMemberMessage;
extern NSString *const GroupUpdatedMessage;
extern NSString *const GroupTitleChangedMessage;
extern NSString *const GroupAvatarChangedMessage;
extern NSString *const GroupMemberLeftMessage;
extern NSString *const GroupMemberJoinedMessage;


@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic, strong, nullable) NSArray<NSString *> *groupMemberIds;
@property (nonatomic, copy, nullable) NSString *groupName;
@property (nonatomic, strong, nullable) NSData *groupId;

#if TARGET_OS_IOS
@property (nullable, nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(nullable NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
- (nullable NSDictionary *)getInfoAboutUpdateTo:(TSGroupModel *)newModel;

#endif

@end

NS_ASSUME_NONNULL_END
