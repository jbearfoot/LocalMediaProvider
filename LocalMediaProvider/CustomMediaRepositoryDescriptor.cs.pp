using System.Collections.Generic;
using EPiServer.Cms.Shell.UI.UIDescriptors;
using EPiServer.Core;
using EPiServer.ServiceLocation;
using EPiServer.Shell;

namespace $rootnamespace$.LocalMediaProvider
{
    [ServiceConfiguration(typeof(IContentRepositoryDescriptor))]
    public class CustomMediaRepositoryDescriptor : MediaRepositoryDescriptor
    {
        private readonly IContentProviderManager _providerManager;
        public CustomMediaRepositoryDescriptor(IContentProviderManager providerManager)
        {
            _providerManager = providerManager;
        }

        public new static string RepositoryKey
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
                return new[] { _providerManager.GetProvider(LocalMediaProviderInitialization.ProviderName).EntryPoint };
            }
        }

    }
}