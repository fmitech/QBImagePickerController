//
//  QBImagePickerController.m
//  QBImagePickerController
//
//  Created by Tanaka Katsuma on 2013/12/30.
//  Copyright (c) 2013 Katsuma Tanaka. All rights reserved.
//

#import "QBAlbumsTableViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>

// Views
#import "QBImagePickerGroupCell.h"
#import "QBAssetsCollectionViewLayout.h"
#import "QBAssetsCollectionViewController.h"

#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>

ALAssetsFilter *ALAssetsFilterFromQBImagePickerControllerFilterType(QBImagePickerControllerFilterType type) {
    switch (type) {
        case QBImagePickerControllerFilterTypeNone:
            return [ALAssetsFilter allAssets];
            break;

        case QBImagePickerControllerFilterTypePhotos:
            return [ALAssetsFilter allPhotos];
            break;

        case QBImagePickerControllerFilterTypeVideos:
            return [ALAssetsFilter allVideos];
            break;
    }
}

@interface QBAlbumsTableViewController () <QBAssetsCollectionViewControllerDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate> // For camera

@property (nonatomic, strong, readwrite) ALAssetsLibrary *assetsLibrary;
@property (nonatomic, copy,   readwrite) NSArray *assetsGroups;
@property (nonatomic, strong, readwrite) NSMutableOrderedSet *selectedAssetURLs;

@end

@implementation QBAlbumsTableViewController

+ (BOOL)isAccessible
{
    return ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary] &&
            [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]);
}

+ (BOOL)cameraIsAccessible
{
    return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
}

- (instancetype)init
{
    self = [super init];
    if(self) {
        [self setupProperties];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Register cell classes
    [self.tableView registerClass:[QBImagePickerGroupCell class] forCellReuseIdentifier:@"GroupCell"];

    self.showsCancelButton = YES;

    // View settings
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 40.0, 0.0);

    // View controller settings
    self.title = NSLocalizedStringFromTable(@"title", @"QBImagePickerController", nil);
}

- (void)setupProperties
{
    // Property settings
    self.selectedAssetURLs = [NSMutableOrderedSet orderedSet];

    if (self.showsPhotostream) {
        self.groupTypes = @[
                            @(ALAssetsGroupSavedPhotos),
                            @(ALAssetsGroupPhotoStream),
                            @(ALAssetsGroupAlbum)
                            ];
    } else {
        self.groupTypes = @[
                            @(ALAssetsGroupSavedPhotos),
                            @(ALAssetsGroupAlbum)
                            ];
    }
    self.filterType = QBImagePickerControllerFilterTypeNone;

    // Create assets library instance
    ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc] init];
    self.assetsLibrary = assetsLibrary;

    self.rightNavigationItemTitle = @"Done";
}

- (void)setShowsPhotostream:(BOOL)showsPhotostream
{
    _showsPhotostream = showsPhotostream;
    if(!_showsPhotostream) {
        [ALAssetsLibrary disableSharedPhotoStreamsSupport];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Load assets groups
    [self loadAssetsGroupsWithTypes:self.groupTypes completion:^(NSArray *assetsGroups) {
        self.assetsGroups = assetsGroups;
        [self.tableView reloadData];
    }];

    // Validation
    [self.navigationItem.rightBarButtonItem setEnabled:[self validateNumberOfSelectionsWithImageCount:[self numberOfSelectedImages]
                                                                                           videoCount:[self numberOfSelectedVideos]]];
    [self.navigationItem.rightBarButtonItem setTitle:self.rightNavigationItemTitle];
}

#pragma mark - Accessors

- (void)setShowsCancelButton:(BOOL)showsCancelButton
{
    _showsCancelButton = showsCancelButton;

    // Show/hide cancel button
    if (showsCancelButton) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
        [self.navigationItem setLeftBarButtonItem:cancelButton animated:NO];
    } else {
        [self.navigationItem setLeftBarButtonItem:nil animated:NO];
    }
}

- (void)setAllowsMultipleSelection:(BOOL)allowsMultipleSelection
{
    _allowsMultipleSelection = allowsMultipleSelection;

    // Show/hide done button
    if (allowsMultipleSelection) {
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:self.rightNavigationItemTitle
            style:UIBarButtonItemStyleDone target:self action:@selector(done:)];
        [self.navigationItem setRightBarButtonItem:doneButton animated:NO];
    } else {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
}

#pragma mark - Actions

- (void)done:(id)sender
{
    [self passSelectedAssetsToDelegate];
}

- (void)cancel:(id)sender
{
    // Delegate
    if (self.delegate && [self.delegate respondsToSelector:@selector(qb_imagePickerControllerDidCancel:)]) {
		[self.delegate qb_imagePickerControllerDidCancel:self];
    }
}

- (void)cameraAction:(id)sender
{
#ifdef DEBUG
    NSLog(@"Opening Camera");
#endif

    UIImagePickerController *cameraPicker = [[UIImagePickerController alloc] init];
//    cameraPicker.allowsEditing = YES;

    NSArray *supportedTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
    NSArray *videoSupported = [supportedTypes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(SELF contains %@)", @"movie"]];
    if([videoSupported count] > 0) {
#ifdef DEBUG
        NSLog(@"Video capture supported");
#endif
    } else {
#ifdef DEBUG
        NSLog(@"Video capture unsupported");
#endif
    }

    cameraPicker.mediaTypes = supportedTypes; // Enable all supported media types
    cameraPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
    cameraPicker.modalPresentationStyle = UIModalPresentationFullScreen;
    cameraPicker.showsCameraControls = YES;
    cameraPicker.delegate = self;

    [self presentViewController:cameraPicker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];

    void (^saveCompletionHandler)(NSURL*, NSError*)= ^(NSURL *assetURL, NSError *error) {
        if(!error && assetURL != nil) {
            [self.selectedAssetURLs addObject:assetURL];
            [self passSelectedAssetsToDelegate];
        }
    };

    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if(UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeImage)) {
#ifdef DEBUG
        NSLog(@"Camera took image");
#endif
        [self.assetsLibrary writeImageToSavedPhotosAlbum:((UIImage*)[info objectForKey:UIImagePickerControllerOriginalImage]).CGImage
                                                metadata:[info objectForKey:UIImagePickerControllerMediaMetadata]
                                         completionBlock:saveCompletionHandler];

    } else if(UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeMovie)) {
#ifdef DEBUG
        NSLog(@"Camera took video");
#endif
        [self.assetsLibrary writeVideoAtPathToSavedPhotosAlbum:[info objectForKey:UIImagePickerControllerMediaURL] completionBlock:saveCompletionHandler];
    }
}

#pragma mark - Validating Selections

- (BOOL)validateNumberOfSelectionsWithImageCount:(NSUInteger)imageCount videoCount:(NSUInteger)videoCount
{
    // Check the number of selected assets
    BOOL qualifiesMinimumNumberOfSelection = (imageCount >= self.minimumNumberOfImageSelection) &&
                                             (videoCount >= self.minimumNumberOfVideoSelection) &&
                                              imageCount + videoCount >= 1;

    BOOL qualifiesMaximumNumberOfSelection = YES;
    if (MAX(1, self.minimumNumberOfImageSelection) <= self.maximumNumberOfImageSelection) {
        qualifiesMaximumNumberOfSelection = (imageCount <= self.maximumNumberOfImageSelection);
    }
    if (MAX(1, self.minimumNumberOfVideoSelection) <= self.maximumNumberOfVideoSelection) {
        qualifiesMaximumNumberOfSelection = qualifiesMaximumNumberOfSelection || (videoCount <= self.maximumNumberOfVideoSelection);
    }

    return (qualifiesMinimumNumberOfSelection && qualifiesMaximumNumberOfSelection);
}

- (NSUInteger)numberOfSelectedImages
{
    NSUInteger imageCount = 0;
    for(NSURL *url in self.selectedAssetURLs) {
        CFStringRef uttype = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[url pathExtension], NULL);
        if (UTTypeConformsTo(uttype, kUTTypeImage)) {
            imageCount++;
        }
        CFRelease(uttype);
    }
    return imageCount;
}

- (NSUInteger)numberOfSelectedVideos
{
    NSUInteger videoCount = 0;
    for(NSURL *url in self.selectedAssetURLs) {
        CFStringRef uttype = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[url pathExtension], NULL);
        if (UTTypeConformsTo(uttype, kUTTypeMovie)) {
            videoCount++;
        }
        CFRelease(uttype);
    }
    return videoCount;
}

#pragma mark - Managing Assets

- (void)loadAssetsGroupsWithTypes:(NSArray *)types completion:(void (^)(NSArray *assetsGroups))completion
{
    __block NSMutableArray *assetsGroups = [NSMutableArray array];
    __block NSUInteger numberOfFinishedTypes = 0;

    for (NSNumber *type in types) {
        __weak typeof(self) weakSelf = self;

        [self.assetsLibrary enumerateGroupsWithTypes:[type unsignedIntegerValue]
                                          usingBlock:^(ALAssetsGroup *assetsGroup, BOOL *stop) {
                                              if (assetsGroup) {
                                                  // Filter the assets group
                                                  [assetsGroup setAssetsFilter:ALAssetsFilterFromQBImagePickerControllerFilterType(weakSelf.filterType)];

                                                  if (assetsGroup.numberOfAssets > 0) {
                                                      // Add assets group
                                                      [assetsGroups addObject:assetsGroup];
                                                  }
                                              } else {
                                                  numberOfFinishedTypes++;
                                              }

                                              // Check if the loading finished
                                              if (numberOfFinishedTypes == types.count) {
                                                  // Sort assets groups
                                                  NSArray *sortedAssetsGroups = [self sortAssetsGroups:(NSArray *)assetsGroups typesOrder:types];

                                                  // Call completion block
                                                  if (completion) {
                                                      completion(sortedAssetsGroups);
                                                  }
                                              }
                                          } failureBlock:^(NSError *error) {
#ifdef DEBUG
                                              NSLog(@"Error: %@", [error localizedDescription]);
#endif
                                          }];
    }
}

- (NSArray *)sortAssetsGroups:(NSArray *)assetsGroups typesOrder:(NSArray *)typesOrder
{
    NSMutableArray *sortedAssetsGroups = [NSMutableArray array];

    for (ALAssetsGroup *assetsGroup in assetsGroups) {
        if (sortedAssetsGroups.count == 0) {
            [sortedAssetsGroups addObject:assetsGroup];
            continue;
        }

        ALAssetsGroupType assetsGroupType = [[assetsGroup valueForProperty:ALAssetsGroupPropertyType] unsignedIntegerValue];
        NSUInteger indexOfAssetsGroupType = [typesOrder indexOfObject:@(assetsGroupType)];

        for (NSInteger i = 0; i <= sortedAssetsGroups.count; i++) {
            if (i == sortedAssetsGroups.count) {
                [sortedAssetsGroups addObject:assetsGroup];
                break;
            }

            ALAssetsGroup *sortedAssetsGroup = sortedAssetsGroups[i];
            ALAssetsGroupType sortedAssetsGroupType = [[sortedAssetsGroup valueForProperty:ALAssetsGroupPropertyType] unsignedIntegerValue];
            NSUInteger indexOfSortedAssetsGroupType = [typesOrder indexOfObject:@(sortedAssetsGroupType)];

            if (indexOfAssetsGroupType < indexOfSortedAssetsGroupType) {
                [sortedAssetsGroups insertObject:assetsGroup atIndex:i];
                break;
            }
        }
    }

    return [sortedAssetsGroups copy];
}

- (void)passSelectedAssetsToDelegate
{
    // Load assets from URLs
    __block NSMutableArray *assets = [NSMutableArray array];

    for (NSURL *selectedAssetURL in self.selectedAssetURLs) {
        __weak typeof(self) weakSelf = self;
        [self.assetsLibrary assetForURL:selectedAssetURL
                            resultBlock:^(ALAsset *asset) {
                                // Add asset
                                [assets addObject:asset];

                                // Check if the loading finished
                                if (assets.count == weakSelf.selectedAssetURLs.count) {
                                    // Delegate
                                    if (self.delegate && [self.delegate respondsToSelector:@selector(qb_imagePickerController:didSelectAssets:)]) {
										[self.delegate qb_imagePickerController:self didSelectAssets:[assets copy]];
                                    }
                                }
                            } failureBlock:^(NSError *error) {
#ifdef DEBUG
                                NSLog(@"Error: %@", [error localizedDescription]);
#endif
                            }];
    }
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.assetsGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    QBImagePickerGroupCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GroupCell" forIndexPath:indexPath];

    ALAssetsGroup *assetsGroup = self.assetsGroups[indexPath.row];
    cell.assetsGroup = assetsGroup;

    return cell;
}


#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 86.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    QBAssetsCollectionViewController *assetsCollectionViewController = [[QBAssetsCollectionViewController alloc] initWithCollectionViewLayout:[QBAssetsCollectionViewLayout layout]];
    assetsCollectionViewController.imagePickerController = self;
    assetsCollectionViewController.filterType = self.filterType;
    assetsCollectionViewController.allowsMultipleSelection = self.allowsMultipleSelection;
    assetsCollectionViewController.minimumNumberOfImageSelection = self.minimumNumberOfImageSelection;
    assetsCollectionViewController.minimumNumberOfVideoSelection = self.minimumNumberOfVideoSelection;
    assetsCollectionViewController.maximumNumberOfImageSelection = self.maximumNumberOfImageSelection;
    assetsCollectionViewController.maximumNumberOfVideoSelection = self.maximumNumberOfVideoSelection;

    ALAssetsGroup *assetsGroup = self.assetsGroups[indexPath.row];
    assetsCollectionViewController.delegate = self;
    assetsCollectionViewController.assetsGroup = assetsGroup;

    for (NSURL *assetURL in self.selectedAssetURLs) {
        [assetsCollectionViewController selectAssetHavingURL:assetURL];
    }

    [self.navigationController pushViewController:assetsCollectionViewController animated:YES];
}


#pragma mark - QBAssetsCollectionViewControllerDelegate

- (void)assetsCollectionViewController:(QBAssetsCollectionViewController *)assetsCollectionViewController didSelectAsset:(ALAsset *)asset
{
    if (self.allowsMultipleSelection) {
        // Add asset URL
        NSURL *assetURL = [asset valueForProperty:ALAssetPropertyAssetURL];
        [self.selectedAssetURLs addObject:assetURL];

        // Validation
        [self.navigationItem.rightBarButtonItem setEnabled:[self validateNumberOfSelectionsWithImageCount:[self numberOfSelectedImages]
                                                                                               videoCount:[self numberOfSelectedVideos]]];
    } else {
        // Delegate
        if (self.delegate && [self.delegate respondsToSelector:@selector(qb_imagePickerController:didSelectAsset:)]) {
			[self.delegate qb_imagePickerController:self didSelectAsset:asset];
        }
    }
}

- (void)assetsCollectionViewController:(QBAssetsCollectionViewController *)assetsCollectionViewController didDeselectAsset:(ALAsset *)asset
{
    if (self.allowsMultipleSelection) {
        // Remove asset URL
        NSURL *assetURL = [asset valueForProperty:ALAssetPropertyAssetURL];
        [self.selectedAssetURLs removeObject:assetURL];

        // Validation
        [self.navigationItem.rightBarButtonItem setEnabled:[self validateNumberOfSelectionsWithImageCount:[self numberOfSelectedImages]
                                                                                               videoCount:[self numberOfSelectedVideos]]];
    }
}

- (void)assetsCollectionViewControllerDidFinishSelection:(QBAssetsCollectionViewController *)assetsCollectionViewController
{
    [self passSelectedAssetsToDelegate];
}
@end
