using System.Collections.Specialized;
using System.Configuration;
using System.Web;
using System.Web.Routing;
using EPiServer;
using EPiServer.Configuration;
using EPiServer.Core;
using EPiServer.DataAccess;
using EPiServer.Framework;
using EPiServer.Framework.Initialization;
using EPiServer.Security;
using EPiServer.ServiceLocation;
using EPiServer.Web;
using EPiServer.Web.Routing;

namespace LocalMediaProvider.LocalMediaProvider
{
    [ModuleDependency(typeof(EPiServer.Web.InitializationModule))]
    public class LocalMediaProviderInitialization : IInitializableModule
    {
        private static string _providerName;

        public static string ProviderName
        {
            get
            {
                if(!string.IsNullOrWhiteSpace(_providerName))
                    return _providerName;

                if (!string.IsNullOrWhiteSpace(ConfigurationManager.AppSettings["LocalMediaContentProviderName"]))
                {
                    _providerName = ConfigurationManager.AppSettings["LocalMediaContentProviderName"];
                }
                else
                {
                    _providerName = "localmedia";
                }
                return _providerName;
            }
            set { _providerName = value; }
        }
        
        public void Initialize(InitializationEngine context)
        {
            //Create provider root if it not exist
            IContentRepository contentRepository = ServiceLocator.Current.GetInstance<IContentRepository>();
            IContent fileRoot = contentRepository.GetBySegment(SiteDefinition.Current.RootPage, ProviderName, LanguageSelector.AutoDetect(true));
            
            if (fileRoot == null)
            {
                fileRoot = contentRepository.GetDefault<ContentFolder>(SiteDefinition.Current.RootPage);
                fileRoot.Name = ProviderName;
                contentRepository.Save(fileRoot, SaveAction.Publish, AccessLevel.NoAccess);
            }

            //Register provider
            const string FullSupportString = "Create,Edit,Delete,Move,Copy,MultiLanguage,PageFolder,Search,Security,Wastebasket";
            //const string almostFullSupportString = "Create";  //,Edit,Delete,Move,Copy,PageFolder,Search,Wastebasket";

            var contentProviderManager = context.Locate.Advanced.GetInstance<IContentProviderManager>();
            NameValueCollection configValues = new NameValueCollection
            {
                {
                    ContentProviderElement.EntryPointString, fileRoot.ContentLink.ToString()
                },
                {
                    "rootPath", ConfigurationManager.AppSettings["LocalMediaContentProviderPath"]
                },
                {
                    ContentProviderElement.CapabilitiesString, FullSupportString
                }

            };
            var provider = context.Locate.Advanced.GetInstance<LocalMediaProvider>();
            provider.Initialize(ProviderName, configValues);
            contentProviderManager.ProviderMap.AddProvider(provider);

            //Since we have our structure outside asset root we register routes for it
            RouteTable.Routes.MapContentRoute(
                name: "LocalMedia",
                url: ProviderName+ "/{node}/{partial}/{action}",
                defaults: new { action = "index" },
                contentRootResolver: s => fileRoot.ContentLink);

            RouteTable.Routes.MapContentRoute(
                name: "LocalMediaEdit",
                url: CmsHomePath + ProviderName + "/{language}/{medianodeedit}/{partial}/{action}",
                defaults: new { action = "index" },
                contentRootResolver: s => fileRoot.ContentLink);
        }

        private static string CmsHomePath
        {
            get
            {
                var cmsContentPath = VirtualPathUtility.AppendTrailingSlash(EPiServer.Shell.Paths.ToResource("CMS", "Content"));
                return VirtualPathUtilityEx.ToAppRelative(cmsContentPath).Substring(1);
            }
        }

        public void Uninitialize(InitializationEngine context)
        { }
    }
}