using System;
using System.Reflection;
using EPiServer.PlugIn;
using EPiServer.Scheduler;
using EPiServer.ServiceLocation;
using log4net;

namespace $rootnamespace$.LocalMediaProvider
{
    [ScheduledPlugIn(DisplayName = "Local Media Provider Job", Description = "Removes the cache for the local provider. New files will then be possible to reach for external users (i.e when going directly to the file address) Fjerner cache fra katalogen WebDAV, slik at man får opp nye filer som er lagt til")]
    public class LocalMediaProviderJob : ScheduledJobBase
    {
        private readonly ILocalMediaProvider _localMediaProvider = ServiceLocator.Current.GetInstance<ILocalMediaProvider>();
        private static readonly ILog _logger = LogManager.GetLogger(MethodBase.GetCurrentMethod().DeclaringType);

        public override string Execute()
        {
            try
            {
                LoadNewFilesFromDisk();
                return "Cache cleared. New files should now be visible and updated";
            }
            catch (Exception ex)
            {
                _logger.Error(ex.Message, ex);
                throw;
            }
        }

        private void LoadNewFilesFromDisk()
        {
            _localMediaProvider.LoadNewContent();
        }
    }
}
