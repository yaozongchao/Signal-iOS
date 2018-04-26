//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "NSString+SSK.h"

NSString *const GroupUpdateTypeSting = @"updateTypeString";
NSString *const GroupInfoString = @"updateInfoString";

NSString *const GroupCreateMessage = @"GROUP_CREATED";
NSString *const GroupBecameMemberMessage = @"GROUP_BECAME_MEMBER";
NSString *const GroupUpdatedMessage = @"GROUP_UPDATED";
NSString *const GroupTitleChangedMessage = @"GROUP_TITLE_CHANGED";
NSString *const GroupAvatarChangedMessage = @"GROUP_AVATAR_CHANGED";
NSString *const GroupMemberLeftMessage = @"GROUP_MEMBER_LEFT";
NSString *const GroupMemberJoinedMessage = @"GROUP_MEMBER_JOINED";

NS_ASSUME_NONNULL_BEGIN

@interface TSGroupModel ()

//@property (nullable, nonatomic) NSString *groupName;

@end

#pragma mark -

@implementation TSGroupModel

#if TARGET_OS_IOS
- (instancetype)initWithTitle:(nullable NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId
{
    OWSAssert(memberIds);

    _groupName              = title;
    _groupMemberIds         = [memberIds copy];
    _groupImage = image; // image is stored in DB
    _groupId                = groupId;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // Occasionally seeing this as nil in legacy data,
    // which causes crashes.
    if (_groupMemberIds == nil) {
        _groupMemberIds = [NSArray new];
    }

    return self;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other {
    if (self == other)
        return YES;
    if (![_groupId isEqualToData:other.groupId]) {
        return NO;
    }
    if (![_groupName isEqual:other.groupName]) {
        return NO;
    }
    if (!(_groupImage != nil && other.groupImage != nil &&
          [UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(other.groupImage)])) {
        return NO;
    }
    NSMutableArray *compareMyGroupMemberIds = [NSMutableArray arrayWithArray:_groupMemberIds];
    [compareMyGroupMemberIds removeObjectsInArray:other.groupMemberIds];
    if ([compareMyGroupMemberIds count] > 0) {
        return NO;
    }
    return YES;
}

- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)newModel contactsManager:(id<ContactsManagerProtocol>)contactsManager {
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    if (![_groupName isEqual:newModel.groupName]) {
        updatedGroupInfoString = [updatedGroupInfoString
            stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""),
                                                               newModel.groupName]];
    }
    if (_groupImage != nil && newModel.groupImage != nil &&
        !([UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(newModel.groupImage)])) {
        updatedGroupInfoString =
            [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"GROUP_AVATAR_CHANGED", @"")];
    }
    if ([updatedGroupInfoString length] == 0) {
        updatedGroupInfoString = NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    NSSet *oldMembers = [NSSet setWithArray:_groupMemberIds];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMemberIds];

    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];

    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];


    if ([membersWhoLeft count] > 0) {
        NSArray *oldMembersNames = [[membersWhoLeft allObjects] map:^NSString*(NSString* item) {
            return [contactsManager displayNameForPhoneIdentifier:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),
                                                           [oldMembersNames componentsJoinedByString:@", "]]];
    }
    
    if ([membersWhoJoined count] > 0) {
        NSArray *newMembersNames = [[membersWhoJoined allObjects] map:^NSString*(NSString* item) {
            return [contactsManager displayNameForPhoneIdentifier:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [newMembersNames componentsJoinedByString:@", "]]];
    }

    return updatedGroupInfoString;
}

- (NSDictionary *)getInfoAboutUpdateTo:(TSGroupModel *)newModel {
    NSString *updateTypeString = @"";
    NSString *updatedGroupInfoString = @"";
    
    BOOL isNewGroup = self.uniqueId == nil && self.groupName == nil;
    if (isNewGroup) {
        return @{
                 GroupUpdateTypeSting: NSLocalizedString(GroupBecameMemberMessage, updateTypeString),
                 GroupInfoString: newModel.groupName
                 };
    }
    
    BOOL groupNameChanged = ![_groupName isEqual:newModel.groupName];
    if (groupNameChanged) {
        return @{
                 GroupUpdateTypeSting: [updateTypeString
                                        stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(GroupTitleChangedMessage, @""),
                                                                 newModel.groupName]],
                 GroupInfoString: newModel.groupName
                 };
    }
    
    BOOL groupAvatarChanged = _groupImage != nil && newModel.groupImage != nil &&
    !([UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(newModel.groupImage)]);
    if (groupAvatarChanged) {
        updateTypeString =
        [updateTypeString stringByAppendingString:NSLocalizedString(GroupAvatarChangedMessage, @"")];
    }
    
    BOOL noUpdateTypeMatched = [updateTypeString length] == 0;
    if (noUpdateTypeMatched) {
        updateTypeString = NSLocalizedString(GroupUpdatedMessage, @"");
    }
    
    NSSet *oldMembers = [NSSet setWithArray:_groupMemberIds];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMemberIds];
    
    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];
    
    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];
    
    if ([membersWhoLeft count] > 0) {
        NSString *oldMembersString = [[membersWhoLeft allObjects] componentsJoinedByString:@", "];
        updateTypeString = [updateTypeString
                            stringByAppendingString:[NSString
                                                     stringWithFormat:NSLocalizedString(GroupMemberLeftMessage, @""),
                                                     oldMembersString]];
        updatedGroupInfoString = oldMembersString;
    }
    
    if ([membersWhoJoined count] > 0) {
        updateTypeString = [NSString stringWithFormat:NSLocalizedString(GroupMemberJoinedMessage, @""),
                            [membersWhoJoined.allObjects componentsJoinedByString:@", "]];
        updatedGroupInfoString = [membersWhoJoined.allObjects componentsJoinedByString:@", "];
    }
    
    return @{
             GroupUpdateTypeSting: updateTypeString,
             GroupInfoString: updatedGroupInfoString
             };
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

@end

NS_ASSUME_NONNULL_END
