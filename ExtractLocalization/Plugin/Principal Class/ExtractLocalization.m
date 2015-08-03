#import "ExtractLocalization.h"
#import "RCXcode.h"
#import "ExtractLocalizationWindowController.h"
#import "EditorLocalizable.h"

static NSString *localizeRegex = @"NSLocalizedString\\s*\\(\\s*@\"(.*)\"\\s*,\\s*(.*)\\s*\\)";
static NSString *stringRegexsObjectiveC = @"@\"[^\"]*\"";
static NSString *stringRegexsSwift = @"\"[^\"]*\"";
static NSString * defaultStringRegex;
static NSString * defaultStringLocalizeRegex;
static NSString * defaultStringLocalizeFormat;
static BOOL  isSwift;

@implementation ExtractLocalization

static id sharedPlugin = nil;

+(void)pluginDidLoad:(NSBundle *)plugin {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPlugin = [[self alloc]initWithBundle:plugin];
    });
}

-(id)initWithBundle:(NSBundle *)bundle{
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createMenuExtractLocalization) name:NSApplicationDidFinishLaunchingNotification object:nil];
    }
    return self;
}

+(BOOL)isSwift{
    return isSwift;
}

- (void)createMenuExtractLocalization {
    NSMenuItem *editMenu = [[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Edit", @"Edit")];
    if (editMenu) {
        NSMenuItem *refactorMenu = [[editMenu submenu] itemWithTitle:NSLocalizedString(@"Refactor", @"Refactor")];
    
        NSMenuItem *extractLocalizationStringMenu = [[NSMenuItem alloc] initWithTitle:@"Extract Localizable String" action:@selector(extractLocalization) keyEquivalent:@"l"];
        [extractLocalizationStringMenu setKeyEquivalentModifierMask:NSShiftKeyMask | NSAlternateKeyMask];
        [extractLocalizationStringMenu setTarget:self];
        
        
//        NSMenuItem *changeLocalizableFile = [[NSMenuItem alloc] initWithTitle:@"Change Localizable File" action:@selector(chooseLocalizableFile) keyEquivalent:@"e"];
//        [changeLocalizableFile setKeyEquivalentModifierMask:NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask];
//        [changeLocalizableFile setTarget:self];

        [[refactorMenu submenu]addItem:extractLocalizationStringMenu];
//        [[refactorMenu submenu]addItem:changeLocalizableFile];
    }
    
}

-(void) chooseLocalizableFile{
    [EditorLocalizable  chooseFileLocalizableString];
}

- (void)extractLocalization {
    RCIDESourceCodeDocument *document = [RCXcode currentSourceCodeDocument];
    NSTextView *textView = [RCXcode currentSourceCodeTextView];
    if (!document || !textView) {
        return;
    }
    NSString * fileExtesion = [[document.displayName componentsSeparatedByString:@"."] objectAtIndex:1];
    
    if ([fileExtesion isEqualToString:@"swift"]) {
        isSwift = YES;
        defaultStringRegex = stringRegexsSwift;
        defaultStringLocalizeRegex =  @"NSLocalizedString\\s*\\(\\s*\"(.*)\"\\s*,\\s*(.*)\\s*\\)";
        defaultStringLocalizeFormat=  @"NSLocalizedString(\"%@\", comment: %@)";
    }else{
        isSwift = NO;
        defaultStringRegex = stringRegexsObjectiveC;
        defaultStringLocalizeRegex = localizeRegex;
        defaultStringLocalizeFormat= @"NSLocalizedString(@\"%@\", %@)";
    }
    self.localizableFilePaths = [EditorLocalizable localizableFilePaths];
    [self searchStringAndCallWindowToEdit:textView];
}

- (void)searchStringAndCallWindowToEdit:(NSTextView *)textView{
    NSArray *selectedRanges = [textView selectedRanges];
    __strong ExtractLocalization * strongSelf = self;
    if ([selectedRanges count] > 0) {
        NSRange range = [[selectedRanges objectAtIndex:0] rangeValue];
        NSRange lineRange = [textView.textStorage.string lineRangeForRange:range];
        NSString *line = [textView.textStorage.string substringWithRange:lineRange];
        
        NSRegularExpression *localizedRex = [[NSRegularExpression alloc] initWithPattern:defaultStringLocalizeRegex options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *localizedMatches = [localizedRex matchesInString:line options:0 range:NSMakeRange(0, [line length])];
        
        NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:defaultStringRegex options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *matches = [regex matchesInString:line options:0 range:NSMakeRange(0, [line length])];
        __block NSUInteger addedLength = 0;
        
        for (int i = 0; i < [matches count]; i++) {
            NSTextCheckingResult *result = [matches objectAtIndex:i];
            NSRange matchedRangeInLine = result.range;
            NSRange matchedRangeInDocument = NSMakeRange(lineRange.location + matchedRangeInLine.location + addedLength, matchedRangeInLine.length);
            if ([self isRange:matchedRangeInLine inSkipedRanges:localizedMatches]) {
                continue;
            }
            NSString *string = [line substringWithRange:matchedRangeInLine];
            if (string.length == 0) {
                continue;
            }
            _extractLocationWindowController =  [[ExtractLocalizationWindowController alloc]initWithWindowNibName:@"ExtractLocalizationWindowController"];
            [_extractLocationWindowController showWindow];
            
            __weak typeof(self) weakSelf = self;
            _extractLocationWindowController.extractLocalizationDidConfirm = ^(ItemLocalizable * item) {
                @try {
                    
                    if (item.key == nil || [item.key isEqualToString:@""]) {
                        NSAlert *alert = [[NSAlert alloc] init];
                        [alert setMessageText:@"Localizable key can not be blank."];
                        [alert setAlertStyle:NSCriticalAlertStyle];
                        [alert runModal];
                        
                        return;
                    }
                    
                    BOOL skipAddingKeyToLocalizable = NO;
                    
                    // Check if key already exist of not.
                    if ([EditorLocalizable checkIfKeyExists:item.key]) {
                        //If key already exists show alert message
                        
                        NSAlert *alert = [[NSAlert alloc] init];
                        [alert setMessageText:@"Localizable key already exists."];
                        [alert setInformativeText:@"Do you want to use this key or cancel?"];
                        [alert setAlertStyle:NSCriticalAlertStyle];
                        
                        NSButton *continueButton = [alert addButtonWithTitle:@"Use this key"];
                        continueButton.keyEquivalent = @"\r";
                        continueButton.tag = NSModalResponseContinue;
                        
                        NSButton *cancelButton = [alert addButtonWithTitle:@"Cancel"];
                        cancelButton.tag = NSModalResponseCancel;
                        cancelButton.keyEquivalent = @"\E";
                        
                        NSModalResponse response = [alert runModal];
                        if (response == NSModalResponseCancel) {
                            return;
                        } else {
                            skipAddingKeyToLocalizable = YES;
                        }
                    }
                    
                    
                    if ([EditorLocalizable checkIfValueExists:item.value] && !skipAddingKeyToLocalizable) {
                        //If key already exists show alert message
                        
                        NSAlert *alert = [[NSAlert alloc] init];
                        [alert setMessageText:@"Alert"];
                        [alert setInformativeText:@"Value already exists in Localizable.strings file. Do you want to create a new entry?"];
                        [alert addButtonWithTitle:@"Create New Key"];
                        [alert addButtonWithTitle:@"Use Existing Key"];
                        [alert setAlertStyle:NSCriticalAlertStyle];
                        
                        NSInteger result =  [alert runModal];
                        if (result == NSAlertSecondButtonReturn ) {
                            skipAddingKeyToLocalizable = YES;
                            item.key = [EditorLocalizable getKeyForValue:item.value];
                        }
                    }
                    
                    if (!skipAddingKeyToLocalizable) {
                        for (NSString* localizableFile in strongSelf.localizableFilePaths) {
                            [EditorLocalizable saveItemLocalizable:item toPath:localizableFile];
                        }
                    }
                    
                    NSString *comment;
                    if ([[ExtractLocalization class] isSwift]) {
                        comment = (item.comment.length) ? [NSString stringWithFormat:@"\"%@\"",item.comment] : @"\"\"";
                    }
                    else {
                        comment = (item.comment.length) ? [NSString stringWithFormat:@"@\"%@\"",item.comment] : @"nil";
                    }
                    
                    NSString *outputString = [NSString stringWithFormat:defaultStringLocalizeFormat, item.key, comment];
                    addedLength = addedLength + outputString.length - string.length;
                    if ([textView shouldChangeTextInRange:matchedRangeInDocument replacementString:outputString]) {
                        [textView.textStorage replaceCharactersInRange:matchedRangeInDocument
                                                  withAttributedString:[[NSAttributedString alloc] initWithString:outputString]];
                        [textView didChangeText];
                    }
                    
                    [[weakSelf.extractLocationWindowController window]orderOut:weakSelf];
                }
                @catch (NSException *exception) {
                    NSLog(@"Save Item Localizable fail %@", exception);
                }
            };
            [_extractLocationWindowController fillFieldValue:string];
        }
    }
}

- (BOOL)isRange:(NSRange)range inSkipedRanges:(NSArray *)ranges {
    for (int i = 0; i < [ranges count]; i++) {
        NSTextCheckingResult *result = [ranges objectAtIndex:i];
        NSRange skippedRange = result.range;
        if (skippedRange.location <= range.location && skippedRange.location + skippedRange.length > range.location + range.length) {
            return YES;
        }
    }
    return NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidFinishLaunchingNotification object:nil];
}

@end
