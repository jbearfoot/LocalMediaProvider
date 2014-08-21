using EPiServer;
using EPiServer.Cms.Shell.UI.UIDescriptors;
using EPiServer.Core;
using EPiServer.ServiceLocation;
using EPiServer.Shell;
using EPiServer.Shell.ViewComposition;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace $rootnamespace$.LocalMediaProvider
{
    [ServiceConfiguration(typeof(IContentRepositoryDescriptor))]
    public class CustomMediaRepositoryDescriptor : MediaRepositoryDescriptor
    {
        private IContentProviderManager _providerManager;
        public CustomMediaRepositoryDescriptor(IContentProviderManager providerManager)
        {
            _providerManager = providerManager;
        }

        public static new string RepositoryKey
        {
            get { return "localmedia"; }
        }

        public override string Key
        {
            get
            {
                return RepositoryKey;
            }
        }

        public override string Name
        {
            get { return "Local media"; }
        }

        public override IEnumerable<ContentReference> Roots
        {
            get
            {
                return new ContentReference[] { _providerManager.GetProvider(LocalMediaProviderInitialization.ProviderName).EntryPoint };
            }
        }
    }

    [Component]
    public class CustomMediaMainNavigationComponent : ComponentDefinitionBase
    {
        public CustomMediaMainNavigationComponent()
            : base("epi-cms.component.Media")
        {
            Categories = new string[] { "content" };
            LanguagePath = "/episerver/cms/components/custommedia";
            SortOrder = 102;
            PlugInAreas = new string[] { PlugInArea.AssetsDefaultGroup };
            Settings.Add(new Setting("repositoryKey", CustomMediaRepositoryDescriptor.RepositoryKey));
        }
    }
}