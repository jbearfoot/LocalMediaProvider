using EPiServer.Construction;
using EPiServer.Core;
using EPiServer.DataAbstraction;
using EPiServer.Framework.Blobs;
using EPiServer.Security;
using EPiServer.Web;
using EPiServer.Web.Routing;
using System;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Linq;
using System.Web;

namespace $rootnamespace$.LocalMediaProvider
{
    public class LocalMediaProvider : ContentProvider
    {
        private IdentityMappingService _identityMappingService;
        private ContentMediaResolver _mediaResolver;

        public LocalMediaProvider(IdentityMappingService identityMappingService, ContentMediaResolver mediaResolver)
        {
            _identityMappingService = identityMappingService;
            _mediaResolver = mediaResolver;
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

        protected override IContent LoadContent(ContentReference contentLink, ILanguageSelector languageSelector)
        {
            var mappedItem = _identityMappingService.Get(contentLink);
            if (mappedItem != null)
            {
                var fileSytemPath = Path.Combine(RootPath, RemoveStartingSlash(mappedItem.ExternalIdentifier.LocalPath).Replace('/','\\'));
                if (Directory.Exists(fileSytemPath))
                {
                    return CreateContentFolder(mappedItem, fileSytemPath);
                }
                else if (File.Exists(fileSytemPath))
                {
                    return CreateMediaData(mappedItem, fileSytemPath);
                }
            }

            return null;
        }


        protected override IList<GetChildrenReferenceResult> LoadChildrenReferencesAndTypes(ContentReference contentLink, string languageID, out bool languageSpecific)
        {
            languageSpecific = false;
            var childrenList = new List<GetChildrenReferenceResult>();

            string currentPath = RootPath;

            if (!EntryPoint.CompareToIgnoreWorkID(contentLink))
            {
                var mappedIdentity = _identityMappingService.Get(contentLink);
                currentPath = Path.Combine(RootPath, RemoveStartingSlash(mappedIdentity.ExternalIdentifier.LocalPath).Replace('/','\\'));
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
                catch(UnauthorizedAccessException)
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
                        Path = mappedFileSystemItems.First(i => i.Uri.Equals(m.ExternalIdentifier)).Path
                    });
                
                foreach (var mappedItem in mappedIdentities)
                {
                    if (Directory.Exists(mappedItem.Path))
                    {
                         childrenList.Add(new GetChildrenReferenceResult(){ContentLink = mappedItem.MappedId.ContentLink, IsLeafNode = false, ModelType = typeof(ContentFolder)});
                    }
                    else if (File.Exists(mappedItem.Path))
                    {
                        var extension = Path.GetExtension(mappedItem.Path);
                        if (!String.IsNullOrEmpty(extension))
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
            return !String.IsNullOrEmpty(virtualPath) && virtualPath[0] == '/' ? virtualPath.Substring(1) : virtualPath;
        }

        private IContent CreateMediaData(MappedIdentity mappedIdentity, string fileSystemPath)
        {
            var localFile = new FileInfo(fileSystemPath);
            var mediaType = _mediaResolver.GetFirstMatching(localFile.Extension);
            if (mediaType == null)
            {
                throw new InvalidOperationException("There is no media type registered for extension: " + localFile.Extension);
            }

            var contentMedia = CreateAndAssignIdentity(mappedIdentity, mediaType, localFile) as IContentMedia;
            contentMedia.BinaryData = new FileBlob(Blob.NewBlobIdentifier(contentMedia.BinaryDataContainer, localFile.Extension), localFile.FullName);
            return contentMedia;
        }

        private IContent CreateContentFolder(MappedIdentity mappedIdentity, string fileSystemPath)
        {
            var localFolder = new DirectoryInfo(fileSystemPath);
            return CreateAndAssignIdentity(mappedIdentity, typeof(ContentFolder), localFolder);

        }

        private IContent CreateAndAssignIdentity(MappedIdentity mappedIdentity, Type modelType, FileSystemInfo fileSystemInfo)
        {
            //Find parent 
            var parentPath = Directory.GetParent(fileSystemInfo.FullName).FullName;
            var parentLink = parentPath.Equals(RootPath, StringComparison.OrdinalIgnoreCase) ?
                EntryPoint :
                _identityMappingService.Get(MappedIdentity.ConstructExternalIdentifier(ProviderKey, RemoveStartingSlash(parentPath.Remove(0, RootPath.Length).Replace('\\', '/')))).ContentLink;

            var content = ContentFactory.CreateContent(ContentTypeRepository.Load(modelType));
            content.ParentLink = parentLink;
            content.ContentGuid = mappedIdentity.ContentGuid;
            content.ContentLink = mappedIdentity.ContentLink;
            content.Name = fileSystemInfo.Name;
            (content as IRoutable).RouteSegment = UrlSegment.GetUrlFriendlySegment(content.Name);

            var securable = content as IContentSecurable;
            securable.GetContentSecurityDescriptor().AddEntry(new AccessControlEntry(EveryoneRole.RoleName, AccessLevel.Read));

            var versionable = content as IVersionable;
            if (versionable != null)
            {
                versionable.Status = VersionStatus.Published;
            }

            var changeTrackable = content as IChangeTrackable;
            if (changeTrackable != null)
            {
                changeTrackable.Changed = DateTime.Now;
            }


            return content;
        }
        
    }
}