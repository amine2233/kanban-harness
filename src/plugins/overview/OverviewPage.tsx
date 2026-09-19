import { Badge, Banner, Button, Card, PageHeader } from '@/design-system'

export function OverviewPage() {
  return (
    <>
      <PageHeader
        title="Overview"
        description="Example plugin page built from design-system components."
        actions={<Button>New item</Button>}
      />
      <Banner tone="info" title="Plugin architecture" className="mb3">
        Every sidebar entry comes from a plugin registered in <code>src/app/plugins.ts</code>.
      </Banner>
      <div className="flex" style={{ gap: 16 }}>
        <Card title="Status" className="flex-auto">
          <Badge variant="new">Ready</Badge>
        </Card>
        <Card title="Buttons" className="flex-auto">
          <div className="hk-button-group">
            <Button variant="secondary">Left</Button>
            <Button variant="secondary">Middle</Button>
            <Button variant="secondary">Right</Button>
          </div>
        </Card>
      </div>
    </>
  )
}
