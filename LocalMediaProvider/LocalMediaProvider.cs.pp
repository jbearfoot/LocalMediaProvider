using System;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Linq;
using System.Web;
using EPiServer;
using EPiServer.Construction;
using EPiServer.Core;
using EPiServer.DataAbstraction;
using EPiServer.DataAccess;
using EPiServer.Framework.Blobs;
using EPiServer.Security;
using EPiServer.ServiceLocation;
using EPiServer.Web;
using EPiServer.Web.Routing;

namespace $rootnamespace$.LocalMediaProvider
{
    public class LocalMediaProvider : ContentProvider, ILocalMediaProvider
    {
        private readonly IdentityMappingService _identityMappingService;
        private readonly ContentMediaResolver _mediaResolver;
        private readonly IContentFactory _contentFactory;
        private readonly IContentTypeRepository _contentTypeRepository;
        private readonly IContentRepository _contentRepository;

        public LocalMediaProvider(IdentityMappingService identityMappingService, ContentMediaResolver mediaResolver,
           IContentTypeRepository contentTypeRepository, IContentRepository contentRepository, IContentFactory contentFactory)
        {
            _identityMappingService = identityMappingService;
            _mediaResolver = mediaResolver;
            _contentFactory = contentFactory;
            _contentTypeRepository = contentTypeRepository;
            _contentRepository = contentRepository;
        }

        public string RootPath { get; set; }

        public override void Initialize(string name, System.Collections.Specialized.NameValueCollection config)
        {
            base.Initialize(name, config);
            RootPath = config["rootPath"];
            if (!Directory.Exists(RootPath))
            {
                throw new ConfigurationErrorsException("rootPath must be set!");
            }
        }
        protected override void SetCacheSettings(ContentReference contentReference, IEnumerable<GetChildrenReferenceResult> children, CacheSettings cacheSettings)
        {
            cacheSettings.CancelCaching = true;
            base.SetCacheSettings(contentReference, children, cacheSettings);
        }

        public override ContentReference Save(IContent content, SaveAction action)
        {
            string parentPath = RootPath;
            var mappedParent = _identityMappingService.Get(content.ParentLink);
            if (mappedParent != null)
            {
                parentPath = Uri.UnescapeDataString(string.Format("{0}{1}", RootPath, mappedParent.ExternalIdentifier.AbsolutePath).Replace('/', '\\'));
            }
            string localPath = Path.Combine(VirtualPathUtility.AppendTrailingSlash(parentPath), content.Name).Replace('/', '\\');
            var mappedContent = _identityMappingService.Get(content.ContentLink);
            var uri = MappedIdentity.ConstructExternalIdentifier(ProviderKey, RemoveStartingSlash(localPath.Remove(0, RootPath.Length).Replace('\\', '/')));
            if (mappedContent == null)
            {
                if (content is MediaData)
                {
                    Blob blobData = ((MediaData)content).BinaryData;
                    using (var stream = blobData.OpenRead() as FileStream)
                    {
                        var fileStream = File.Create(localPath);
                        stream.CopyTo(fileStream);
                        fileStream.Close();
                    }
                }
                if (content is ContentFolder)
                {
                    Directory.CreateDirectory(localPath);
                }
            }
            else
            {
                // renaming of folders
                if (content is ContentFolder)
                {
                    var oldPath = GetPhysicalPath(mappedContent.ExternalIdentifier);
                    if (oldPath != localPath)
                    {
                        var children = _contentRepository.GetDescendents(content.ContentLink);
                        foreach (var child in children)
                        {
                            var childContent = LoadContent(child, null);
                            var childMapping = _identityMappingService.Get(child);
                            var oldAbsolutePath = mappedContent.ExternalIdentifier.AbsolutePath;
                            var newAbsolutePath = uri.AbsolutePath;
                            var newChildPath = new Uri(childMapping.ExternalIdentifier.ToString().Replace(oldAbsolutePath, newAbsolutePath));
                            _identityMappingService.Delete(new List<Guid>() { childMapping.ContentGuid });
                            _identityMappingService.MapContent(newChildPath, childContent);
                        }
                        Directory.Move(oldPath, localPath);
                        ClearProviderPagesFromCache();
                    }
                    _identityMappingService.Delete(new List<Guid>() { content.ContentGuid });
                    return _identityMappingService.MapContent(uri, content).ContentLink;
                }
            }
            var mapping = _identityMappingService.Get(uri, true);
            LoadNewContent();
            return mapping.ContentLink;
        }

        protected override IContent LoadContent(ContentReference contentLink, ILanguageSelector languageSelector)
        {
            var mappedItem = _identityMappingService.Get(contentLink);
            if (mappedItem != null)
            {
                var fileSytemPath = GetPhysicalPath(mappedItem.ExternalIdentifier);
                if (Directory.Exists(fileSytemPath))
                {
                    return CreateContentFolder(mappedItem, fileSytemPath);
                }
                if (File.Exists(fileSytemPath))
                {
                    return CreateMediaData(mappedItem, fileSytemPath);
                }
            }
            return null;
        }

        protected override IList<GetChildrenReferenceResult> LoadChildrenReferencesAndTypes(ContentReference contentLink, string languageId, out bool languageSpecific)
        {
            languageSpecific = true;
            var childrenList = new List<GetChildrenReferenceResult>();
            string currentPath = RootPath;
            if (EntryPoint != null && !EntryPoint.CompareToIgnoreWorkID(contentLink))
            {
                var mappedIdentity = _identityMappingService.Get(contentLink);
                currentPath = GetPhysicalPath(mappedIdentity.ExternalIdentifier);
            }
            var directoryInfo = new DirectoryInfo(currentPath);
            if (directoryInfo.Exists)
            {
                //Have not found a way to check access without having to use try/catch
                FileSystemInfo[] fileSystemInfos;
                try
                {
                    fileSystemInfos = directoryInfo.GetFileSystemInfos();
                }
                catch (UnauthorizedAccessException)
                {
                    return childrenList;
                }

                var mappedFileSystemItems = fileSystemInfos
                        .Select(f => new
                        {
                            Path = f.FullName,
                            Uri = MappedIdentity.ConstructExternalIdentifier(ProviderKey, RemoveStartingSlash(f.FullName.Remove(0, RootPath.Length).Replace('\\', '/')))
                        });
                var mappedIdentities = _identityMappingService.List(mappedFileSystemItems.Select(f => f.Uri), true)
                    .Select(m => new
                    {
                        MappedId = m,
                        Path = mappedFileSystemItems.FirstOrDefault(i => i.Uri.ToString().ToLower().Equals(m.ExternalIdentifier.ToString().ToLower())).Path
                    });

                foreach (var mappedItem in mappedIdentities)
                {
                    if (Directory.Exists(mappedItem.Path))
                    {
                        childrenList.Add(new GetChildrenReferenceResult() { ContentLink = mappedItem.MappedId.ContentLink, IsLeafNode = false, ModelType = typeof(ContentFolder) });
                    }
                    else if (File.Exists(mappedItem.Path))
                    {
                        var extension = Path.GetExtension(mappedItem.Path);
                        if (!string.IsNullOrEmpty(extension))
                        {
                            var mediaType = _mediaResolver.GetFirstMatching(extension);
                            if (mediaType == null)
                            {
                                throw new InvalidOperationException("There is no media type registered for extension: " + extension);
                            }
                            childrenList.Add(new GetChildrenReferenceResult() { ContentLink = mappedItem.MappedId.ContentLink, IsLeafNode = true, ModelType = mediaType });
                        }
                    }
                }
            }
            return childrenList;
        }

        private string RemoveStartingSlash(string virtualPath)
        {
            return !string.IsNullOrEmpty(virtualPath) && virtualPath[0] == '/' ? virtualPath.Substring(1) : virtualPath;
        }

        private IContent CreateMediaData(MappedIdentity mappedIdentity, string fileSystemPath)
        {
            var localFile = new FileInfo(fileSystemPath);
            var mediaType = _mediaResolver.GetFirstMatching(localFile.Extension);
            if (mediaType == null)
            {
                throw new InvalidOperationException("There is no media type registered for extension: " + localFile.Extension);
            }

            IContentMedia contentMedia = CreateAndAssignIdentity(mappedIdentity, mediaType, localFile) as IContentMedia;
            if (contentMedia != null)
            {
                contentMedia.BinaryData = new FileBlob(Blob.NewBlobIdentifier(contentMedia.BinaryDataContainer, localFile.Extension), localFile.FullName);
            }
            return contentMedia;
        }

        private IContent CreateContentFolder(MappedIdentity mappedIdentity, string fileSystemPath)
        {
            var localFolder = new DirectoryInfo(fileSystemPath);
            return CreateAndAssignIdentity(mappedIdentity, typeof(ContentFolder), localFolder);
        }

        private IContent CreateAndAssignIdentity(MappedIdentity mappedIdentity, Type modelType, FileSystemInfo fileSystemInfo)
        {
            var parentPath = Directory.GetParent(fileSystemInfo.FullName).FullName;
            ContentReference parentLink = null;

            if (parentPath.Equals(RootPath, StringComparison.OrdinalIgnoreCase))
            {
                parentLink = EntryPoint;
            }
            else
            {
                var parentIdentity = MappedIdentity.ConstructExternalIdentifier(ProviderKey,
                    RemoveStartingSlash(parentPath.Remove(0, RootPath.Length).Replace('\\', '/')));
                var mappedParentIdentity = _identityMappingService.Get(parentIdentity, true);
                parentLink = mappedParentIdentity.ContentLink;
            }
            var contentType = _contentTypeRepository.Load(modelType);
            IContent content = _contentFactory.CreateContent(_contentTypeRepository.Load(modelType), new BuildingContext(contentType)
            {
                Parent = _contentRepository.Get<ContentFolder>(parentLink)
            });
            content.ParentLink = parentLink;
            content.ContentGuid = mappedIdentity.ContentGuid;
            content.ContentLink = mappedIdentity.ContentLink;
            content.ContentTypeID = _contentTypeRepository.Load(modelType).ID;
            content.Name = fileSystemInfo.Name;
            if (content is IRoutable)
            {
                (content as IRoutable).RouteSegment = UrlSegment.GetUrlFriendlySegment(content.Name);
            }

            if (content is IContentSecurable)
            {
                IContentSecurable securable = content as IContentSecurable;
                securable.GetContentSecurityDescriptor().AddEntry(new AccessControlEntry(EveryoneRole.RoleName, AccessLevel.Read));
            }

            var versionable = content as IVersionable;
            if (versionable != null)
            {
                versionable.Status = VersionStatus.Published;
            }
            var changeTrackable = content as IChangeTrackable;
            if (changeTrackable != null)
            {
                changeTrackable.Changed = fileSystemInfo.LastWriteTime;
            }
            return content;
        }

        private string GetPhysicalPath(Uri externalIdentifier)
        {
            return Path.Combine(RootPath, RemoveStartingSlash(externalIdentifier.LocalPath).Replace('/', '\\'));
        }

        public void LoadNewContent()
        {
            IContentRepository contentRepository = ServiceLocator.Current.GetInstance<IContentRepository>();
            IContent fileRoot = contentRepository.GetBySegment(SiteDefinition.Current.RootPage, LocalMediaProviderInitialization.ProviderName, LanguageSelector.AutoDetect(true));
            string cacheKey = DependencyHelper.Service.ContentCacheKeyCreator.CreateChildrenCacheKey(fileRoot.ContentLink, null);
            DependencyHelper.Service.CacheInstance.Remove(cacheKey);
        }
    }

    public interface ILocalMediaProvider
    {
        void LoadNewContent();
    }
}