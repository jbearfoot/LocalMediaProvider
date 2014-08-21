using EPiServer;
using EPiServer.Configuration;
using EPiServer.Core;
using EPiServer.DataAccess;
using EPiServer.Framework;
using EPiServer.Framework.Initialization;
using EPiServer.Security;
using EPiServer.Web;
using EPiServer.Web.Routing;
using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Linq;
using System.Web;
using System.Web.Routing;

namespace $rootnamespace$.LocalMediaProvider
{
    [ModuleDependency(typeof(EPiServer.Web.InitializationModule))]
    public class LocalMediaProviderInitialization : IInitializableModule
    {
        public const string ProviderName = "localfiles";

        public void Initialize(InitializationEngine context)
        {
            //Create provider root if it not exist
            var contentRepository = context.Locate.ContentRepository();
            var fileRoot = contentRepository.GetBySegment(SiteDefinition.Current.RootPage, ProviderName, LanguageSelector.AutoDetect(true));
            if (fileRoot == null)
            {
                fileRoot = contentRepository.GetDefault<ContentFolder>(SiteDefinition.Current.RootPage);
                fileRoot.Name = ProviderName;
                contentRepository.Save(fileRoot, SaveAction.Publish, AccessLevel.NoAccess);
            }

            //Register provider
            var contentProviderManager = context.Locate.Advanced.GetInstance<IContentProviderManager>();
            var configValues = new NameValueCollection();
            configValues.Add(ContentProviderElement.EntryPointString, fileRoot.ContentLink.ToString());
            configValues.Add("rootPath", "C:\\");
            var provider = context.Locate.Advanced.GetInstance<LocalMediaProvider>();
            provider.Initialize(ProviderName, configValues);
            contentProviderManager.ProviderMap.AddProvider(provider);

            //Since we have our structure outside asset root we register routes for it
            RouteTable.Routes.MapContentRoute(
                name: "LocalMedia",
                url: "localfiles/{node}/{partial}/{action}",
                defaults: new { action = "index" },
                contentRootResolver: (s) => fileRoot.ContentLink);

            RouteTable.Routes.MapContentRoute(
                name: "LocalMediaEdit",
                url: CmsHomePath + "localfiles/{language}/{medianodeedit}/{partial}/{action}",
                defaults: new { action = "index" },
                contentRootResolver: (s) => fileRoot.ContentLink);
        }

        private static string CmsHomePath
        {
            get
            {
                var cmsContentPath = VirtualPathUtility.AppendTrailingSlash(EPiServer.Shell.Paths.ToResource("CMS", "Content"));
                return VirtualPathUtilityEx.ToAppRelative(cmsContentPath).Substring(1);
            }
        }

        public void Preload(string[] parameters)
        {}

        public void Uninitialize(EPiServer.Framework.Initialization.InitializationEngine context)
        {}
    }
}