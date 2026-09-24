// Maps each LUI node kind onto the WinUI control used to render it. Layout
// containers use Grid (star tracks express `grow`, Column/RowSpacing express
// `gap`); leaf controls map to their WinUI counterparts.

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace LUI.WinUI
{
    internal static class LUIElementFactory
    {
        public static FrameworkElement Create(LUINodeKind kind)
        {
            switch (kind)
            {
                case LUINodeKind.Root:
                case LUINodeKind.Stack:
                case LUINodeKind.Resizable:
                case LUINodeKind.Split:
                    return new Grid();
                case LUINodeKind.Row:
                case LUINodeKind.Column:
                case LUINodeKind.Grid:
                case LUINodeKind.ListContainer:
                case LUINodeKind.VirtualList:
                case LUINodeKind.ButtonGroup:
                case LUINodeKind.ToggleGroup:
                case LUINodeKind.Tabs:
                case LUINodeKind.Breadcrumb:
                case LUINodeKind.Pagination:
                case LUINodeKind.Tree:
                case LUINodeKind.Table:
                case LUINodeKind.TableRow:
                case LUINodeKind.InputGroupActions:
                case LUINodeKind.Toolbar:
                case LUINodeKind.Stepper:
                case LUINodeKind.Timeline:
                case LUINodeKind.RadioGroup:
                    return new LUIGrid();
                case LUINodeKind.Panel:
                case LUINodeKind.Card:
                case LUINodeKind.Box:
                case LUINodeKind.Bubble:
                    return new Border { Child = new LUIGrid() };
                case LUINodeKind.Alert:
                    return new InfoBar { IsOpen = true, IsClosable = false };
                case LUINodeKind.Text:
                case LUINodeKind.Heading:
                case LUINodeKind.Paragraph:
                case LUINodeKind.Label:
                    return new TextBlock();
                case LUINodeKind.Button:
                    return new Button();
                case LUINodeKind.ToggleButton:
                    return new ToggleButton();
                case LUINodeKind.Toggle:
                    return new ToggleSwitch();
                case LUINodeKind.Radio:
                    return new RadioButton();
                case LUINodeKind.Slider:
                    return new Slider { Minimum = 0, Maximum = 1 };
                case LUINodeKind.TextField:
                case LUINodeKind.Input:
                    return new TextBox();
                case LUINodeKind.SecureField:
                    return new PasswordBox();
                case LUINodeKind.SearchField:
                    return new AutoSuggestBox();
                case LUINodeKind.Textarea:
                    return new TextBox
                    {
                        AcceptsReturn = true,
                        TextWrapping = TextWrapping.Wrap,
                    };
                case LUINodeKind.Combobox:
                    return new AutoSuggestBox();
                case LUINodeKind.Checkbox:
                    return new CheckBox();
                case LUINodeKind.SwitchControl:
                    return new ToggleSwitch();
                case LUINodeKind.Progress:
                    return new ProgressBar { Minimum = 0, Maximum = 1 };
                case LUINodeKind.Divider:
                    return new Border();
                case LUINodeKind.Scroll:
                    return new ScrollViewer
                    {
                        Content = new LUIGrid(),
                        HorizontalScrollBarVisibility =
                            ScrollBarVisibility.Auto,
                        VerticalScrollBarVisibility =
                            ScrollBarVisibility.Auto,
                    };
                case LUINodeKind.Spacer:
                    return new Border();
                case LUINodeKind.Spinner:
                    return new ProgressRing { IsActive = true };
                case LUINodeKind.Icon:
                    return new FontIcon();
                case LUINodeKind.Select:
                    return new DropDownButton();
                case LUINodeKind.MenuItem:
                    // MenuItems render inside a flyout; a placeholder grid is
                    // created so the element map stays complete.
                    return new Grid { Visibility = Visibility.Collapsed };
                case LUINodeKind.ListItem:
                    return new LUIListItem();
                case LUINodeKind.Avatar:
                    return new PersonPicture();
                case LUINodeKind.Image:
                    return new Image();
                case LUINodeKind.MediaSurface:
                    return new Border();
                case LUINodeKind.Step:
                    return new LUIGrid();
                case LUINodeKind.TimelineItem:
                    return new LUIGrid();
                case LUINodeKind.InputGroup:
                    return new Border { Child = new LUIGrid() };
                case LUINodeKind.TableCell:
                    return new Border { Child = new TextBlock() };
                case LUINodeKind.Accordion:
                    return new Expander();
                case LUINodeKind.Dialog:
                case LUINodeKind.Drawer:
                case LUINodeKind.Sheet:
                    // Modal surfaces are presented by LUIModalPresenter; their
                    // element is the body content the presenter hosts.
                    return new Border { Child = new LUIGrid() };
                case LUINodeKind.Tooltip:
                    // Renders inline as plain text when the parent is not a
                    // `stack` (stack attaches it as an overlay instead).
                    return new TextBlock();
                case LUINodeKind.DropdownMenu:
                case LUINodeKind.ContextMenu:
                    return new Grid { Visibility = Visibility.Collapsed };
                case LUINodeKind.Toast:
                    return new InfoBar { IsClosable = true };
                case LUINodeKind.BottomTabs:
                    return new Grid();
                case LUINodeKind.BottomTab:
                    return new LUIGrid();
                case LUINodeKind.StatusBar:
                    return new Border { Child = new TextBlock() };
                default:
                    return new Grid();
            }
        }
    }

    // A Grid subclass that tags itself as the LUI children host so the sync
    // engine can find the panel inside wrapper controls (Border.Child etc.).
    internal class LUIGrid : Grid { }

    // ListItem: a host panel so the element map finds its children surface.
    internal class LUIListItem : LUIGrid { }
}
