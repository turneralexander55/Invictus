/* Invictus: "I've saved my files" page for Calamares.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shown after the partition page. It says in plain words what the install
 * is about to do to the disk (from the partition page's choice in Global
 * Storage), names the systems Calamares found there (os-prober), and keeps
 * Next ("Install") disabled until the person ticks the box. The box starts
 * unticked every time the page is shown.
 */
#include "DiskCheckViewStep.h"

#include "GlobalStorage.h"
#include "JobQueue.h"

#include <QCheckBox>
#include <QFont>
#include <QLabel>
#include <QStringList>
#include <QVBoxLayout>
#include <QWidget>

CALAMARES_PLUGIN_FACTORY_DEFINITION( DiskCheckViewStepFactory, registerPlugin< DiskCheckViewStep >(); )

namespace
{
// "/dev/sda1:Windows 11:Windows:chain" -> "Windows 11"
QStringList
foundSystems( const Calamares::GlobalStorage* gs )
{
    QStringList names;
    const auto lines = gs->value( QStringLiteral( "osproberLines" ) ).toStringList();
    for ( const QString& line : lines )
    {
        const QStringList parts = line.split( QLatin1Char( ':' ) );
        const QString name = parts.value( 1 ).trimmed();
        if ( !name.isEmpty() && !names.contains( name ) )
        {
            names << name;
        }
    }
    return names;
}
}  // namespace

DiskCheckViewStep::DiskCheckViewStep( QObject* parent )
    : Calamares::ViewStep( parent )
    , m_widget( new QWidget )
    , m_title( new QLabel )
    , m_found( new QLabel )
    , m_warning( new QLabel )
    , m_saved( new QCheckBox )
{
    auto* layout = new QVBoxLayout( m_widget );
    layout->setContentsMargins( 48, 48, 48, 48 );
    layout->setSpacing( 20 );

    QFont titleFont = m_title->font();
    titleFont.setPointSizeF( titleFont.pointSizeF() * 1.6 );
    m_title->setFont( titleFont );
    m_title->setWordWrap( true );
    m_title->setObjectName( QStringLiteral( "diskCheckTitle" ) );
    m_found->setWordWrap( true );
    m_found->setObjectName( QStringLiteral( "diskCheckFound" ) );
    m_warning->setWordWrap( true );
    m_warning->setObjectName( QStringLiteral( "diskCheckWarning" ) );
    m_saved->setObjectName( QStringLiteral( "diskCheckSaved" ) );
    m_saved->setText( tr( "I've saved the photos and files I want to keep." ) );

    layout->addWidget( m_title );
    layout->addWidget( m_found );
    layout->addWidget( m_warning );
    layout->addSpacing( 12 );
    layout->addWidget( m_saved );
    layout->addStretch();

    connect( m_saved, &QCheckBox::toggled, this, [ this ]( bool ) { emit nextStatusChanged( isNextEnabled() ); } );
}

DiskCheckViewStep::~DiskCheckViewStep()
{
    if ( m_widget && m_widget->parent() == nullptr )
    {
        m_widget->deleteLater();
    }
}

QString
DiskCheckViewStep::prettyName() const
{
    return tr( "Your files" );
}

QWidget*
DiskCheckViewStep::widget()
{
    return m_widget;
}

bool
DiskCheckViewStep::isNextEnabled() const
{
    return m_saved->isChecked();
}

bool
DiskCheckViewStep::isBackEnabled() const
{
    return true;
}

bool
DiskCheckViewStep::isAtBeginning() const
{
    return true;
}

bool
DiskCheckViewStep::isAtEnd() const
{
    return true;
}

Calamares::JobList
DiskCheckViewStep::jobs() const
{
    return Calamares::JobList();
}

void
DiskCheckViewStep::onActivate()
{
    const auto* gs = Calamares::JobQueue::instance()->globalStorage();
    const QString choice
        = gs->value( QStringLiteral( "partitionChoices" ) ).toMap().value( QStringLiteral( "install" ) ).toString();
    const QStringList found = foundSystems( gs );
    const QString foundText = found.isEmpty() ? QString() : tr( "Found: %1." ).arg( found.join( QStringLiteral( ", " ) ) );

    if ( choice == QLatin1String( "alongside" ) )
    {
        m_title->setText( tr( "Invictus will go next to what is already on this computer." ) );
        m_found->setText( foundText.isEmpty() ? QString() : foundText + QLatin1Char( ' ' ) + tr( "It stays, with less space." ) );
        m_warning->setText( tr( "Changing a disk can go wrong. Save anything you can't lose first." ) );
    }
    else if ( choice == QLatin1String( "replace" ) )
    {
        m_title->setText( tr( "Invictus will replace one part of the disk." ) );
        m_found->setText( foundText );
        m_warning->setText( tr( "Everything on that part is erased. This can't be undone." ) );
    }
    else if ( choice == QLatin1String( "manual" ) )
    {
        m_title->setText( tr( "Invictus will change the disk the way you set it up." ) );
        m_found->setText( foundText );
        m_warning->setText( tr( "Partitions you chose to format are erased. This can't be undone." ) );
    }
    else
    {
        m_title->setText( tr( "Invictus will replace everything on this computer." ) );
        m_found->setText( foundText.isEmpty() ? tr( "No other system was found, but files may still be on the disk." )
                                              : foundText );
        m_warning->setText( tr( "Everything on the disk is erased. This can't be undone." ) );
    }
    m_found->setVisible( !m_found->text().isEmpty() );

    // Unticked every time: going back and changing the disk means deciding again.
    m_saved->setChecked( false );
    emit nextStatusChanged( false );
}

void
DiskCheckViewStep::setConfigurationMap( const QVariantMap& configurationMap )
{
    const QString text = configurationMap.value( QStringLiteral( "checkbox" ) ).toString();
    if ( !text.isEmpty() )
    {
        m_saved->setText( text );
    }
}
