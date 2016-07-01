using EPiServer.Shell;
using EPiServer.Shell.ViewComposition;

namespace $rootnamespace$.LocalMediaProvider
{
    [Component]
    public class CustomMediaMainNavigationComponent : ComponentDefinitionBase
    {
        public CustomMediaMainNavigationComponent() : base("epi-cms.component.Media")
        {
            Categories = new[] { "content" };
            LanguagePath = "/episerver/cms/components/custommedia";
            SortOrder = 102;
            PlugInAreas = new[] { PlugInArea.AssetsDefaultGroup };
            Settings.Add(new Setting("repositoryKey", CustomMediaRepositoryDescriptor.RepositoryKey));
        }
    }
}